#!/bin/bash

# Path to the configuration file
CONFIG_FILE="${HIVE_HOME}/conf/metastore-site.xml"

# Function to check if a property exists and is not empty
check_property() {
    local property_name=$1
    local property_value=$(xmlstarlet sel -t -v "//property[name='$property_name']/value" $CONFIG_FILE)
    
    if [ -z "$property_value" ]; then
        echo "Error: Property ${property_name} is not set or is empty."
        exit 1
    else
        echo "Property ${property_name} is set to ${property_value}."
    fi
}

# Function to validate the JDBC URL
validate_jdbc_url() {
    local jdbc_url=$(xmlstarlet sel -t -v "//property[name='javax.jdo.option.ConnectionURL']/value" $CONFIG_FILE)
    if [[ ! "$jdbc_url" =~ ^jdbc:postgresql:// ]]; then
        echo "Error: Invalid JDBC URL format. It should start with 'jdbc:postgresql://'."
        exit 1
    else
        echo "JDBC URL format is valid."
    fi
}

# Function to validate the JDBC driver
validate_jdbc_driver() {
    local driver_name=$(xmlstarlet sel -t -v "//property[name='javax.jdo.option.ConnectionDriverName']/value" $CONFIG_FILE)
    if [[ "$driver_name" != "org.postgresql.Driver" ]]; then
        echo "Error: Invalid JDBC driver. It should be 'org.postgresql.Driver'."
        exit 1
    else
        echo "JDBC driver is valid."
    fi
}

# Check necessary properties
check_property "javax.jdo.option.ConnectionURL"
check_property "javax.jdo.option.ConnectionDriverName"
check_property "javax.jdo.option.ConnectionUserName"
check_property "javax.jdo.option.ConnectionPassword"

# Validate the JDBC URL and driver
validate_jdbc_url
validate_jdbc_driver

echo "All necessary properties are set correctly and valid."
