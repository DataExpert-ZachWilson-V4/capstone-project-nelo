import argparse
import json
import logging
import requests
import time
import random
from concurrent.futures import ThreadPoolExecutor, as_completed
from kafka import KafkaProducer, KafkaAdminClient
from kafka.admin import NewTopic
from kafka.errors import TopicAlreadyExistsError
import pandas as pd
from pydantic import BaseModel, ValidationError, Field
from typing import Optional, List, Dict

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

bootstrap_servers = ['kafka1:9092', 'kafka2:9093', 'kafka3:9094']

def create_topic(topic_name):
    try:
        admin_client = KafkaAdminClient(
            bootstrap_servers=bootstrap_servers,
            client_id='text_descriptions'
        )
        topic_list = [NewTopic(name=topic_name, num_partitions=5, replication_factor=3)]
        existing_topics = admin_client.list_topics()

        if topic_name not in existing_topics:
            admin_client.create_topics(new_topics=topic_list, validate_only=False)
            logger.info(f"Topic '{topic_name}' created successfully.")
        else:
            logger.info(f"Topic '{topic_name}' already exists.")
    except TopicAlreadyExistsError:
        logger.info(f"Topic '{topic_name}' already exists.")
    except Exception as e:
        logger.error(f"Failed to create Kafka topic: {e}")

def create_producer():
    try:
        producer = KafkaProducer(
            bootstrap_servers=bootstrap_servers,
            value_serializer=lambda x: json.dumps(x).encode('utf-8'),
            retries=10,
            max_block_ms=60000,
            request_timeout_ms=240000,
            acks='all',
        )
        logger.info("Kafka Producer created successfully.")
        return producer
    except Exception as e:
        logger.error(f"Failed to create Kafka Producer: {e}")
        raise

# Base URL for the GraphQL request
base_url = "https://data-graph.mlb.com/graphql/"

# Pydantic models
class Tag(BaseModel):
    slug: Optional[str] = None
    type: Optional[str] = None
    title: Optional[str] = None
    gamePk: Optional[int] = None

class Article(BaseModel):
    contentDate: Optional[str] = None
    description: Optional[str] = None
    headline: Optional[str] = None
    slug: Optional[str] = None
    blurb: Optional[str] = None
    templateUrl: Optional[str] = None
    type: Optional[str] = None
    tags: Optional[List[Tag]] = None

class VideoContent(BaseModel):
    headline: Optional[str] = None
    duration: Optional[int] = None
    title: Optional[str] = None
    description: Optional[str] = None
    slug: Optional[str] = None
    blurb: Optional[str] = None
    date: Optional[str] = None
    contentDate: Optional[str] = None
    playbacks: Optional[List[Dict[str, str]]] = None
    tags: Optional[List[Tag]] = None

class GameContent(BaseModel):
    recapArticle: Optional[List[Article]] = None
    relatedArticles: Optional[List[Article]] = None
    videoContent: Optional[List[VideoContent]] = None

class Game(BaseModel):
    gamePk: int
    gameDate: Optional[str] = None
    content: Optional[GameContent] = None

class APIResponse(BaseModel):
    getGamesByGamePks: List[Game]

# GraphQL query and operation name
operation_name = "getGamesByGamePks"
query = """
fragment mediaTags on Tag {
    ... on GameTag {
        slug
        type
        title
        gamePk
    }
    ... on TaxonomyTag {
        slug
        type
        title
    }
    ... on InternalTag {
        slug
        type
        title
    }
    ... on TeamTag {
        type
        team {
            id
        }
    }
}
fragment articleFields on Article {
    contentDate
    description
    headline
    slug
    blurb: summary
    templateUrl: thumbnail
    type
    tags {
        ...mediaTags
    }
}
query getGamesByGamePks($gamePks: [Int], $locale: Language, $gameRecapTags: [String]!, $relatedArticleTags: [String]!, $contentSource: ContentSource) {
    getGamesByGamePks(gamePks: $gamePks) {
        gamePk
        gameDate
        content {
            videoContent(locale: $locale) {
                headline
                duration
                title
                description
                slug
                id: slug
                blurb
                guid: playGuid
                date: contentDate
                contentDate
                preferredPlaybackScenarioURL(preferredPlaybacks: ["hlsCloud", "mp4Avc"])
                playbacks: playbackScenarios {
                    name: playback
                    url: location
                }
                thumbnail {
                    templateUrl
                }
                tags {
                    ...mediaTags
                }
            }
            ... on GameContent {
                recapArticle: articleContent(locale: $locale, tags: $gameRecapTags, limit: 1, contentSource: $contentSource) {
                    ...articleFields
                }
                relatedArticles: articleContent(locale: $locale, tags: $relatedArticleTags, excludeTags: $gameRecapTags, limit: 5) {
                    ...articleFields
                }
            }
        }
    }
}
"""

def check_game_existence(game_id):
    variables = {
        "gameRecapTags": ["game-recap"],
        "relatedArticleTags": ["storytype-article"],
        "gamePks": [game_id],
        "locale": "EN_US",
        "contentSource": "MLB"
    }

    # Construct the payload
    payload = {
        "operationName": operation_name,
        "query": query,
        "variables": variables
    }

    # Make the POST request
    response = requests.post(base_url, json=payload)
    return response.status_code == 200

# Function to send data to Kafka
def send_to_kafka(producer, topic_name, data, game_id):
    try:
        producer.send(topic_name, value=data)
        logger.info(f"Sent data for game ID {game_id} to Kafka.")
    except Exception as e:
        logger.error(f"Failed to send data for game ID {game_id} to Kafka: {e}")

# Function to collect and send data
def collect_and_send_data(producer, topic_name, start_game_number, end_game_number):
    max_workers = 40  # Increased max_workers to 40
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_game = {executor.submit(fetch_and_process_game_data, producer, topic_name, game_id): game_id for game_id in range(start_game_number, end_game_number + 1)}

        for future in as_completed(future_to_game):
            game_id = future_to_game[future]
            try:
                future.result()
            except Exception as e:
                logger.error(f"Error processing game ID {game_id}: {e}")

def fetch_and_process_game_data(producer, topic_name, game_id):
    if not check_game_existence(game_id):
        logger.warning(f"Game data for game ID {game_id} does not exist. Skipping.")
        return

    variables = {
        "gameRecapTags": ["game-recap"],
        "relatedArticleTags": ["storytype-article"],
        "gamePks": [game_id],
        "locale": "EN_US",
        "contentSource": "MLB"
    }

    # Construct the payload
    payload = {
        "operationName": operation_name,
        "query": query,
        "variables": variables
    }

    # Make the POST request
    response = requests.post(base_url, json=payload)

    # Handle the response
    if response.status_code == 200:
        try:
            data = response.json()

            # Validate data with Pydantic model
            validated_data = APIResponse(getGamesByGamePks=data['data']['getGamesByGamePks'])
            validated_data_dict = validated_data.dict()

            # Flatten videoContent
            video_df = pd.json_normalize(validated_data_dict['getGamesByGamePks'],
                                         record_path=['content', 'videoContent'],
                                         meta=['gamePk', 'gameDate'],
                                         record_prefix='video_',
                                         meta_prefix='game_')

            # Select and rename important columns
            columns = [
                'game_gamePk', 'game_gameDate', 'video_headline', 'video_duration', 'video_title', 'video_description',
                'video_slug', 'video_blurb', 'video_date', 'video_contentDate'
            ]

            video_df = video_df[columns]
            video_df.columns = [
                'gamePk', 'gameDate', 'headline', 'duration', 'title', 'description', 'slug', 'blurb', 'date', 'contentDate'
            ]

            # Remove duplicate rows
            video_df = video_df.drop_duplicates()

            # Send each row as a message to Kafka
            for index, row in video_df.iterrows():
                send_to_kafka(producer, topic_name, row.to_dict(), game_id)

        except ValidationError as val_err:
            logger.error(f"Data validation error for game ID {game_id}: {val_err}")
        except Exception as e:
            logger.error(f"Error processing game ID {game_id}: {e}")
    else:
        logger.error(f"Query failed for game ID {game_id} with status code {response.status_code}: {response.text}")

def parse_args():
    parser = argparse.ArgumentParser(description="Kafka Producer for MLB Data")
    parser.add_argument('--start_game', type=int, required=True, help="Start game number")
    parser.add_argument('--end_game', type=int, required=True, help="End game number")
    parser.add_argument('--topic', type=str, required=True, help="Kafka topic name")
    return parser.parse_args()

def main():
    args = parse_args()
    create_topic(args.topic)
    producer = create_producer()
    collect_and_send_data(producer, args.topic, args.start_game, args.end_game)
    producer.close()

if __name__ == "__main__":
    main()
