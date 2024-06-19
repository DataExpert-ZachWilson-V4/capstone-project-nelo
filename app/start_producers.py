import os
import subprocess
import logging
import argparse
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Semaphore, Thread
from queue import Queue, Full
import requests
from pydantic import BaseModel, Field, ValidationError
from typing import Optional

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Map each producer script to its corresponding Kafka topic
producer_script_to_topic = {
    'boxscores_producer.py': 'boxscore_info',
    'allplaysinfo_producer.py': 'allplays_info',
    'gameresults_producer.py': 'game_results',
    'officialsinfo_producer.py': 'officials_info',
    'pitchersinfo_producer.py': 'pitchers_info',
    'playersinfo_producer.py': 'players_info',
    'text_descriptions_producer.py': 'text_descriptions',
    'venueinfo_producer.py': 'venue_info',
    'weatherinfo_producer.py': 'weather_info'
}

def check_game_existence(game_number):
    url = f"https://ws.statsapi.mlb.com/api/v1.1/game/{game_number}/feed/live?language=en"
    response = requests.head(url, timeout=20)
    return response.status_code == 200

class CustomThreadFactory:
    def __init__(self, name_prefix):
        self.name_prefix = name_prefix
        self.counter = 0

    def __call__(self):
        self.counter += 1
        thread = Thread()
        thread.name = f"{self.name_prefix}-{self.counter}"
        return thread

def start_puller(script_name, start_game, end_game, puller_id, topic, semaphore):
    script_path = os.path.join('/app/producers', script_name)
    if not os.path.isfile(script_path):
        logger.error(f"Script not found: {script_path}")
        semaphore.release()
        return

    # Check if the game data exists before processing
    for game_number in range(start_game, end_game + 1):
        if not check_game_existence(game_number):
            logger.warning(f"Game data for game {game_number} does not exist. Skipping.")
            continue

        command = f"python {script_path} --start_game {game_number} --end_game {game_number} --topic {topic}"
        try:
            process = subprocess.Popen(command, shell=True)
            process.wait()
            logger.info(f"Started puller {puller_id} for game {game_number} using {script_name} with topic {topic}")
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to start puller {puller_id} using {script_name}: {e}")
        except Exception as e:
            logger.error(f"An error occurred while starting puller {puller_id} using {script_name}: {e}")

    semaphore.release()

def main():
    parser = argparse.ArgumentParser(description="Start Pullers for MLB Data")
    parser.add_argument('start_game_number', type=int, help='Start game number')
    parser.add_argument('end_game_number', type=int, help='End game number')
    args = parser.parse_args()

    start_game_number = args.start_game_number
    end_game_number = args.end_game_number
    total_pullers = 40  
    batch_size = 8  
    max_concurrent_pullers = 8  
    game_range = end_game_number - start_game_number + 1
    games_per_puller = game_range // total_pullers

    semaphore = Semaphore(max_concurrent_pullers)
    queue = Queue(max_concurrent_pullers)
    thread_factory = CustomThreadFactory(name_prefix="puller-thread")

    def custom_rejected_execution_handler(runnable, executor):
        logger.error(f"Task {runnable} rejected from {executor}")
        try:
            queue.put(runnable, timeout=10)
        except Full:
            logger.error(f"Queue is full, task {runnable} could not be added.")

    producer_scripts = [
        'boxscores_producer.py', 
        'allplaysinfo_producer.py', 
        'gameresults_producer.py', 
        'linescoreinfo_producer.py', 
        'officialsinfo_producer.py', 
        'pitchersinfo_producer.py', 
        'playersinfo_producer.py', 
        'text_descriptions_producer.py', 
        'venueinfo_producer.py', 
        'weatherinfo_producer.py'
    ]

    with ThreadPoolExecutor(
        max_workers=40,  
        thread_name_prefix='puller-thread-',
    ) as executor:
        futures = []
        for script_name in producer_scripts:
            kafka_topic = producer_script_to_topic.get(script_name)
            for i in range(total_pullers):
                start_game = start_game_number + i * games_per_puller
                end_game = start_game_number + (i + 1) * games_per_puller - 1
                if i == total_pullers - 1:
                    end_game = end_game_number

                semaphore.acquire()
                futures.append(executor.submit(start_puller, script_name, start_game, end_game, i + 1, kafka_topic, semaphore))

                if len(futures) >= batch_size:
                    for future in as_completed(futures):
                        try:
                            future.result()
                        except Exception as e:
                            logger.error(f"An error occurred: {e}")
                    futures = []

                    time.sleep(6)

        for future in as_completed(futures):
            try:
                future.result()
            except Exception as e:
                logger.error(f"An error occurred: {e}")

if __name__ == '__main__':
    main()
