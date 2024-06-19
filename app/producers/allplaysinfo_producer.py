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
from typing import Optional, Dict

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

bootstrap_servers = ['kafka1:9092', 'kafka2:9093', 'kafka3:9094']

def create_topic(topic_name):
    try:
        admin_client = KafkaAdminClient(
            bootstrap_servers=bootstrap_servers,
            client_id='allplays_info'
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

producer = create_producer()

class GameData(BaseModel):
    pk: int

class DateTimeInfo(BaseModel):
    originalDate: Optional[str] = None
    time: Optional[str] = None

class AllPlaysData(BaseModel):
    allPlays: list

class LiveData(BaseModel):
    plays: AllPlaysData

class GameDataStructure(BaseModel):
    gameData: Dict[str, GameData]
    datetime: Dict[str, DateTimeInfo]
    liveData: Dict[str, LiveData]

def check_game_existence(game_number):
    url = f"https://ws.statsapi.mlb.com/api/v1.1/game/{game_number}/feed/live?language=en"
    response = requests.head(url, timeout=10)
    return response.status_code == 200

def fetch_game_data(game_number):
    if not check_game_existence(game_number):
        logger.warning(f"Game data for game {game_number} does not exist. Skipping.")
        return None
    
    url = f"https://ws.statsapi.mlb.com/api/v1.1/game/{game_number}/feed/live?language=en"
    retries = 5
    backoff_factor = 0.5

    for attempt in range(retries):
        try:
            response = requests.get(url, timeout=20)
            response.raise_for_status()
            data = response.json()

            # Validate data with Pydantic model
            validated_data = GameDataStructure(**data)
            return validated_data.dict()
        except requests.HTTPError as http_err:
            logger.error(f"HTTP error occurred for game {game_number}: {http_err}")
        except requests.RequestException as req_err:
            logger.error(f"Request error occurred for game {game_number}: {req_err}")
        except ValidationError as val_err:
            logger.error(f"Data validation error for game {game_number}: {val_err}")
        except Exception as err:
            logger.error(f"Other error occurred for game {game_number}: {err}")

        sleep_time = backoff_factor * (2 ** attempt) + random.uniform(0, 1)
        logger.info(f"Retrying in {sleep_time:.2f} seconds...")
        time.sleep(sleep_time)
    
    return None

def process_allplays_data(data):
    try:
        game_id = data['gameData']['game']['pk']
        game_date = data['gameData']['datetime'].get('originalDate', 'N/A')
        game_time = data['gameData']['datetime'].get('time', 'N/A')
    except KeyError as e:
        logger.error(f"Missing key in gameData: {e}")
        return None

    if 'allPlays' in data['liveData']['plays']:
        try:
            all_plays_info = pd.json_normalize(data['liveData']['plays']['allPlays'])
            all_plays_info['game_id'] = game_id
            all_plays_info['game_date'] = game_date
            all_plays_info['game_time'] = game_time
            all_plays_info.columns = [f"allPlays_{col}" if col not in ['game_id', 'game_date', 'game_time'] else col for col in all_plays_info.columns]
            return all_plays_info
        except Exception as e:
            logger.error(f"Error processing allPlays: {e}")
            return None
    return None

def send_data_to_kafka(producer, topic, records):
    for record in records:
        for attempt in range(10):  
            try:
                producer.send(topic, record).get(timeout=60)
                break
            except Exception as e:
                logger.error(f"Error sending data to Kafka: {e}")
                time.sleep(5)

def stream_allplays_data(start_game_number, end_game_number, topic):
    max_workers = 40  
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_game = {executor.submit(fetch_game_data, game_number): game_number for game_number in range(start_game_number, end_game_number + 1)}

        for future in as_completed(future_to_game):
            game_number = future_to_game[future]
            try:
                data = future.result()
                if data:
                    allplays_data_frame = process_allplays_data(data)
                    if allplays_data_frame is not None:
                        records = allplays_data_frame.to_dict(orient='records')
                        send_data_to_kafka(producer, topic, records)
                        logger.info(f"Successfully sent allPlays data for game {game_number} to Kafka.")
                    else:
                        logger.info(f"No valid allPlays data for game {game_number}.")
                else:
                    logger.info(f"No data for game {game_number}.")
            except Exception as e:
                logger.error(f"Error processing game {game_number}: {e}")

def parse_args():
    parser = argparse.ArgumentParser(description="Kafka Producer for MLB Data")
    parser.add_argument('--start_game', type=int, required=True, help="Start game number")
    parser.add_argument('--end_game', type=int, required=True, help="End game number")
    parser.add_argument('--topic', type=str, required=True, help="Kafka topic name")
    return parser.parse_args()

def main():
    args = parse_args()
    create_topic(args.topic)
    stream_allplays_data(args.start_game, args.end_game, args.topic)

if __name__ == "__main__":
    main()
