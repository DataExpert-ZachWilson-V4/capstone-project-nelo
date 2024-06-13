#!/bin/bash

set -e

if [ "$1" = 'superset' ]; then
  echo "Initializing the database..."
  superset db upgrade

  echo "Creating default roles and permissions..."
  superset init

  echo "Creating default user..."
  export FLASK_APP=superset
  superset fab create-admin \
    --username $ADMIN_USERNAME \
    --firstname $ADMIN_FIRSTNAME \
    --lastname $ADMIN_LASTNAME \
    --email $ADMIN_EMAIL \
    --password $ADMIN_PASSWORD

  echo "Loading example data..."
  superset load_examples

  echo "Adding PostgreSQL connection..."
  cat <<EOF > /app/superset/datasource_config.yaml
databases:
- database_name: Superset Postgres
  sqlalchemy_uri: postgresql+psycopg2://${AZURE_POSTGRES_USERNAME}:${AZURE_POSTGRES_PASSWORD}@${AZURE_POSTGRES_HOST}:${AZURE_POSTGRES_PORT}/${AZURE_SUPERSET_DB}
EOF

  superset import-datasources --path /app/superset/datasource_config.yaml

  echo "Starting the Superset server..."
  superset run -h 0.0.0.0 -p 8088 --with-threads --reload --debugger
fi

exec "$@"
