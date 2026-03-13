#!/usr/bin/env bash

KAFKA_HOME=/opt/kafka
CONFIG="$KAFKA_HOME/config/connect-distributed.properties"

update_connect_configs() {
  env | grep '^CONNECT_' | while IFS='=' read -r KEY VALUE; do
    prop_name=$(echo "${KEY#CONNECT_}" | tr '[:upper:]' '[:lower:]' | tr '_' '.')
    if grep -qE "^#?$prop_name=" "$CONFIG"; then  
      sed -i "s|^#\?$prop_name=.*|$prop_name=$VALUE|" "$CONFIG"
    else
      echo "$prop_name=$VALUE" >> "$CONFIG"
    fi
  done 
}

update_connect_configs

$KAFKA_HOME/bin/connect-distributed.sh $CONFIG

: << 'END'
This Bash script dynamically configures Kafka Connect by converting environment variables
prefixed with CONNECT_ into properties in the distributed connector config file,
then starts the Connect worker.

Uses env | grep '^CONNECT_' to find CONNECT_* vars
For each, strips CONNECT_, converts to lowercase with dots
Checks if the property exists (commented or not) via grep -qE "^#?$prop_name="
Updates via sed (stream editor) -i (in-place) if found, appends via echo if new
Finally runs $KAFKA_HOME/bin/connect-distributed.sh $CONFIG

Example:
CONNECT_BOOTSTRAP_SERVERS=kafka:9092  => connect.bootstrap.servers=kafka:9092
CONNECT_GROUP_ID=connect-cluster      => connect.group.id=connect-cluster

END