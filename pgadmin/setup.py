import os
import json
from pgadmin4 import create_app
from pgadmin4.pgadmin import db, User, Server
from flask import current_app

app = create_app()
app.app_context().push()

# Ensure the database is created
with current_app.app_context():
    db.create_all()

# Read environment variables
env_vars = {
    "AZURE_POSTGRES_USERNAME": os.getenv("AZURE_POSTGRES_USERNAME"),
    "AZURE_POSTGRES_PASSWORD": os.getenv("AZURE_POSTGRES_PASSWORD"),
    "AZURE_AIRFLOW_DB": os.getenv("AZURE_AIRFLOW_DB"),
    "AZURE_SUPERSET_DB": os.getenv("AZURE_SUPERSET_DB"),
    "AZURE_HIVE_DB": os.getenv("AZURE_HIVE_DB"),
    "AZURE_MLFLOW_DB": os.getenv("AZURE_MLFLOW_DB"),
    "AZURE_HAYSTACK_DB": os.getenv("AZURE_HAYSTACK_DB"),
    "AZURE_ZOOKEEPER_DB": os.getenv("AZURE_ZOOKEEPER_DB"),
    "AZURE_KAFKA_DB": os.getenv("AZURE_KAFKA_DB"),
    "AZURE_TRINO_DB": os.getenv("AZURE_TRINO_DB"),
    "AZURE_QDRANT_DB": os.getenv("AZURE_QDRANT_DB"),
    "AZURE_SPARK_DB": os.getenv("AZURE_SPARK_DB")
}

with open('/pgadmin/servers.json') as f:
    servers = json.load(f)['Servers']

admin = User.query.filter_by(email='admin@example.com').first()

if not admin:
    admin = User(
        email='admin@example.com',
        password='admin',
        active=True
    )
    db.session.add(admin)
    db.session.commit()

for server_id, server_info in servers.items():
    existing_server = Server.query.filter_by(name=server_info['Name'], user_id=admin.id).first()
    if not existing_server:
        maintenance_db = env_vars[f"AZURE_{server_info['Name'].split()[0].upper()}_DB"]
        server = Server(
            user_id=admin.id,
            servergroup_id=1,
            name=server_info['Name'],
            host=server_info['Host'],
            port=server_info['Port'],
            maintenance_db=maintenance_db,
            username=env_vars["AZURE_POSTGRES_USERNAME"],
            password=env_vars["AZURE_POSTGRES_PASSWORD"],
            ssl_mode=server_info['SSLMode'],
        )
        db.session.add(server)

db.session.commit()
