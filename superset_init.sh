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
  datasource_config_path="/app/superset/datasource_config.yaml"
  new_content=$(cat <<EOF
databases:
- database_name: Superset Postgres
  sqlalchemy_uri: postgresql+psycopg2://${AZURE_POSTGRES_USERNAME}:${AZURE_POSTGRES_PASSWORD}@${AZURE_POSTGRES_HOST}:${AZURE_POSTGRES_PORT}/${AZURE_SUPERSET_DB}
EOF
)

  if ! grep -q "${AZURE_POSTGRES_HOST}" "$datasource_config_path"; then
    echo "$new_content" >> "$datasource_config_path"
    echo "PostgreSQL connection added to datasource_config.yaml"
  else
    echo "PostgreSQL connection already exists in datasource_config.yaml"
  fi

  superset import-datasources --path "$datasource_config_path"

  echo "Starting the Superset server..."
  superset run -h 0.0.0.0 -p 8088 --with-threads --reload --debugger
fi

exec "$@"
