#!/bin/bash

# Custom setup or checks can go here
echo "Running custom setup tasks..."

# Run the pgAdmin setup script if the database does not exist
if [ ! -f /var/lib/pgadmin/pgadmin4.db ]; then
    echo "Setting up pgAdmin configuration"
    /usr/bin/python3 /pgadmin/setup.py
fi

# Call the original entry point script to start pgAdmin
exec /entrypoint.sh
