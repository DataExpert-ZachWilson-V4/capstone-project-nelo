#!/bin/bash

# This script sets up and updates Kafka brokers by generating a unique cluster ID 
# and configuring meta.properties files for each broker.

# Directory to store the shared cluster ID
CLUSTER_ID_DIR="/var/lib/kafka/cluster_id"
CLUSTER_ID_FILE="${CLUSTER_ID_DIR}/cluster_id"

# Create the directory if it doesn't exist
mkdir -p ${CLUSTER_ID_DIR}

# Function to generate a new cluster ID
generate_cluster_id() {
  CLUSTER_ID=$(kafka-storage.sh random-uuid)
  echo "${CLUSTER_ID}" > ${CLUSTER_ID_FILE}
}

# Function to read the cluster ID
read_cluster_id() {
  if [ -f ${CLUSTER_ID_FILE} ]; then
    CLUSTER_ID=$(cat ${CLUSTER_ID_FILE})
  else
    generate_cluster_id
  fi
}

# Function to update meta.properties
update_meta_properties() {
  BROKER_ID=$1
  DATA_DIR=$2
  # Clear the data directory if it exists
  rm -rf ${DATA_DIR}/*
  # Create the data directory if it doesn't exist
  mkdir -p ${DATA_DIR}
  # Create the meta.properties file
  echo "version=0" > ${DATA_DIR}/meta.properties
  echo "broker.id=${BROKER_ID}" >> ${DATA_DIR}/meta.properties
  echo "cluster.id=${CLUSTER_ID}" >> ${DATA_DIR}/meta.properties
}

# Read or generate the cluster ID
generate_cluster_id

# Update meta.properties for brokers
update_meta_properties 1 /var/lib/kafka/data1
update_meta_properties 2 /var/lib/kafka/data2
update_meta_properties 3 /var/lib/kafka/data3

echo "Cluster ID: ${CLUSTER_ID} has been set for all brokers."