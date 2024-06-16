#!/bin/bash

# Self-setting execute permissions
if [ ! -x "$0" ]; then
  chmod +x "$0"
fi

RESOURCE_GROUP_NAME=$1
PUBLIC_IP_NAME=$2

if [ -z "$RESOURCE_GROUP_NAME" ] || [ -z "$PUBLIC_IP_NAME" ]; then
  echo "{\"exists\": \"false\"}"
  exit 1
fi

IP_EXISTS=$(az network public-ip show --resource-group "$RESOURCE_GROUP_NAME" --name "$PUBLIC_IP_NAME" --query "ipAddress" --output tsv 2>/dev/null)

if [ -n "$IP_EXISTS" ]; then
  echo "{\"exists\": \"true\"}"
else
  echo "{\"exists\": \"false\"}"
fi
