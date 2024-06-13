import os
import subprocess
import logging
import argparse
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Semaphore

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def start_puller(start_game, end_game, puller_id, topic, semaphore):
    script_path = os.path.join('/app', 'boxscores_producer.py')
    if not os.path.isfile(script_path):
        logger.error(f"Script not found: {script_path}")
        semaphore.release()
        return

    command = f"python {script_path} --start_game {start_game} --end_game {end_game} --topic {topic}"
    retry_attempts = 3
    for attempt in range(retry_attempts):
        try:
            process = subprocess.Popen(command, shell=True)
            process.wait()
            logger.info(f"Started puller {puller_id} for games {start_game} to {end_game}")
            break
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to start puller {puller_id} (attempt {attempt+1}): {e}")
        except Exception as e:
            logger.error(f"An error occurred while starting puller {puller_id} (attempt {attempt+1}): {e}")
        finally:
            if attempt == retry_attempts - 1:
                semaphore.release()

def main():
    parser = argparse.ArgumentParser(description="Start Pullers for MLB Data")
    parser.add_argument('start_game_number', type=int, help='Start game number')
    parser.add_argument('end_game_number', type=int, help='End game number')
    args = parser.parse_args()

    start_game_number = args.start_game_number
    end_game_number = args.end_game_number
    total_pullers = 44
    batch_size = 2  # Reduced batch size
    max_concurrent_pullers = 2  # Reduced number of concurrent pullers
    game_range = end_game_number - start_game_number + 1
    games_per_puller = game_range // total_pullers
    kafka_topic = 'boxscore_info'

    semaphore = Semaphore(max_concurrent_pullers)

    with ThreadPoolExecutor(max_workers=max_concurrent_pullers) as executor:
        futures = []
        for i in range(total_pullers):
            start_game = start_game_number + i * games_per_puller
            end_game = start_game_number + (i + 1) * games_per_puller - 1
            if i == total_pullers - 1:
                end_game = end_game_number

            semaphore.acquire()
            futures.append(executor.submit(start_puller, start_game, end_game, i + 1, kafka_topic, semaphore))

            if len(futures) >= batch_size:
                for future in as_completed(futures):
                    try:
                        future.result()
                    except Exception as e:
                        logger.error(f"An error occurred: {e}")
                futures = []

                # Added sleep time to further reduce resource usage
                time.sleep(5)

        for future in as_completed(futures):
            try:
                future.result()
            except Exception as e:
                logger.error(f"An error occurred: {e}")

if __name__ == '__main__':
    main()
