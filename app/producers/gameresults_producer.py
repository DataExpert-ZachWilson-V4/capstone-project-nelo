import numpy as np
from datetime import datetime, timedelta
import json
import logging
import requests
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from kafka import KafkaProducer, KafkaAdminClient
from kafka.admin import NewTopic
from kafka.errors import TopicAlreadyExistsError
import pandas as pd
from pydantic import BaseModel, ValidationError, Field
from typing import List, Optional, Dict

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

bootstrap_servers = ['kafka1:9092', 'kafka2:9093', 'kafka3:9094']

def create_topic(topic_name):
    try:
        admin_client = KafkaAdminClient(
            bootstrap_servers=bootstrap_servers,
            client_id='game_results'
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

class LeagueRecord(BaseModel):
    wins: Optional[int] = None
    losses: Optional[int] = None
    pct: Optional[str] = None

class Team(BaseModel):
    id: int
    name: str

class TeamData(BaseModel):
    team: Team
    score: Optional[int] = None
    isWinner: Optional[bool] = None
    leagueRecord: Optional[LeagueRecord] = None

class GameTeams(BaseModel):
    away: TeamData
    home: TeamData

class Game(BaseModel):
    gamePk: int
    season: str
    officialDate: str
    teams: GameTeams

class DateInfo(BaseModel):
    date: str
    totalItems: int
    totalEvents: int
    totalGames: int
    totalGamesInProgress: int
    games: List[Game]

class ScheduleData(BaseModel):
    dates: List[DateInfo]

def check_game_existence(start_date, end_date, game_type):
    start_formatted_date = start_date.strftime('%Y-%m-%d')
    end_formatted_date = end_date.strftime('%Y-%m-%d')
    url = f'https://statsapi.mlb.com/api/v1/schedule?sportId=1&startDate={start_formatted_date}&endDate={end_formatted_date}&timeZone=America/New_York&gameType={game_type}&language=en&leagueId=104&leagueId=103&leagueId=160&leagueId=590&hydrate=team,linescore(matchup,runners),xrefId,story,flags,statusFlags,broadcasts(all),venue(location),decisions,person,probablePitcher,stats,game(content(media(epg),summary),tickets),seriesStatus(useOverride=true)&sortBy=gameDate,gameStatus,gameType'
    response = requests.head(url, timeout=10)
    return response.status_code == 200

def fetch_and_send_data(producer, start_date, end_date, game_type):
    if not check_game_existence(start_date, end_date, game_type):
        logger.warning(f"No game data found from {start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')} for game type {game_type}. Skipping.")
        return
    
    try:
        start_formatted_date = start_date.strftime('%Y-%m-%d')
        end_formatted_date = end_date.strftime('%Y-%m-%d')
        api_url = f'https://statsapi.mlb.com/api/v1/schedule?sportId=1&startDate={start_formatted_date}&endDate={end_formatted_date}&timeZone=America/New_York&gameType={game_type}&language=en&leagueId=104&leagueId=103&leagueId=160&leagueId=590&hydrate=team,linescore(matchup,runners),xrefId,story,flags,statusFlags,broadcasts(all),venue(location),decisions,person,probablePitcher,stats,game(content(media(epg),summary),tickets),seriesStatus(useOverride=true)&sortBy=gameDate,gameStatus,gameType'
        
        response = requests.get(url=api_url)
        response.raise_for_status()
        data = response.json()
        
        # Validate data with Pydantic model
        validated_data = ScheduleData(**data)
        
        if validated_data.dates:
            for date_info in validated_data.dates:
                for game in date_info.games:
                    game_data = {}
                    for side in ['away', 'home']:
                        team_data = getattr(game.teams, side)
                        team_info = pd.json_normalize(team_data.team.dict())
                        team_info[f'{side}_score'] = team_data.score
                        team_info[f'{side}_isWinner'] = team_data.isWinner
                        if team_data.leagueRecord:
                            team_info[f'{side}_leagueRecord_wins'] = team_data.leagueRecord.wins
                            team_info[f'{side}_leagueRecord_losses'] = team_data.leagueRecord.losses
                            team_info[f'{side}_leagueRecord_pct'] = team_data.leagueRecord.pct

                        team_info.columns = [f'{side}_team_{col}' for col in team_info.columns]
                        df_side = team_info
                        game_data[side] = df_side.to_dict(orient='records')

                    game_data['game_id'] = game.gamePk
                    game_data['season'] = game.season
                    game_data['game_date'] = game.officialDate

                    # Send data to Kafka
                    producer.send('game_results', value=game_data)
            logger.info(f'Data from {start_formatted_date} to {end_formatted_date} for game type {game_type} sent to Kafka successfully.')
        else:
            logger.info(f'No games found from {start_formatted_date} to {end_formatted_date} for game type {game_type}. Skipping to next dates.')
    except requests.HTTPError as http_err:
        logger.error(f"HTTP error occurred: {http_err}")
    except ValidationError as val_err:
        logger.error(f"Data validation error occurred: {val_err}")
    except Exception as err:
        logger.error(f"Other error occurred: {err}")

producer = create_producer()

# User-defined year range
start_year = 2023
end_year = datetime.now().year

# MLB season start and end months and days
season_start_month = 2
season_start_day = 19
season_end_month = 11
season_end_day = 22

# Defining game types in a list
game_types = ['R', 'A', 'P', 'F', 'D', 'L', 'W', 'S']

def process_year(year):
    start_date = datetime(year, season_start_month, season_start_day)
    end_date = datetime(year, season_end_month, season_end_day)
    
    current_date = start_date
    while current_date <= end_date:
        batch_end_date = min(current_date + timedelta(days=29), end_date)
        for game_type in game_types:
            fetch_and_send_data(producer, current_date, batch_end_date, game_type)
        current_date = batch_end_date + timedelta(days=1)
        lag = np.random.uniform(1, 3)
        logger.info(f'Waiting {round(lag, 1)} seconds before next request.')
        time.sleep(lag)

with ThreadPoolExecutor(max_workers=40) as executor:  # Increased max_workers to 40
    futures = [executor.submit(process_year, year) for year in range(start_year, end_year + 1)]
    for future in as_completed(futures):
        try:
            future.result()
        except Exception as e:
            logger.error(f"Error processing year: {e}")

logger.info('All data has been collected and sent to Kafka.')

# Close the Kafka producer
producer.close()
