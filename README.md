# STILL IN PROGRESS
# MORE UPDATES TO BE ADDED DAILY.

# MLB Game Stats Pipeline/Predictor/Chat-Bot

Since I'm using Windows, I installed Ubuntu with Windows Subsystem for Linux (WSL 2) and used Docker Desktop and VS Code to complete this project.

### On Ubuntu, download GitHub CLI: 
`sudo apt update`

`sudo apt install gh`

### Authenticate with your preferred method:
`gh auth login`

### In VS Code:
#### Clone & move into the repo directory:
`gh repo clone DataExpert-ZachWilson-V4/capstone-project-nelo-mlb-stats`

`cd capstone-project-nelo-mlb-stats`

### Start Services
Run `docker-compose up -d` in root directory.

### When done:
#### Clean Up Docker Environment
Run `./clean_docker.sh`

## Overview
This project involves fetching historical & current MLB game stats from MLB.com API. Processing and storing the data in IceBerg tables. Training multiple ML models to predict future game stats of the current season, and storing these predictions back into Iceberg tables. As the days change, the future tables are overwritten daily to update predictions for upcoming games starting from the next day. The future date entries in these tables are shifted forward to the next future date, and the previous future day's data is replaced with the actual game data. Airflow will orchestrate the workflow on a daily schedule. All tables are converted to text embeddings using OpenAI's embeddings and stored in a Qdrant vector store. A RAG model is set up to retrieve the embeddings in Qdrant that match closest to the query embeddings generated by SentenceTransformers and combines into text prompts. These prompts are fed into OpenAI's GPT-3.5-turbo, which generates responses to user queries. The responses from OpenAI GPT are then displayed in the Streamlit app. The responses can also be converted to an audio file using gTTS (Google Text-to-Speech) and played back within the Streamlit app.

## Data Retrieval/Storage Process

## ML Process

## RAG Model/Chat UI Process

![MLB Diagram](/MLB_Diagram.png)

## Tables

