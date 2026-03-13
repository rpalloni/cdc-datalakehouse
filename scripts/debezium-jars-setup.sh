#!/bin/bash

# Debezium 3.3 PostgreSQL connector download script
# Downloads only the Postgres connector JARs from official Maven repository

DEBEZIUM_VERSION="3.3.2.Final"
DOWNLOAD_DIR="custom-plugins"
PLUGIN_URL="https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/${DEBEZIUM_VERSION}/debezium-connector-postgres-${DEBEZIUM_VERSION}-plugin.tar.gz"

echo "Downloading Debezium PostgreSQL $DEBEZIUM_VERSION connector..."

# Download Postgres connector plugin
mkdir -p $DOWNLOAD_DIR
cd $DOWNLOAD_DIR
wget -q "$PLUGIN_URL"

if [ $? -eq 0 ]; then
    echo "✓ Downloaded debezium-connector-postgres-${DEBEZIUM_VERSION}-plugin.tar.gz"
    
    # Extract the tar.gz
    tar -xzf "debezium-connector-postgres-${DEBEZIUM_VERSION}-plugin.tar.gz"
    rm "debezium-connector-postgres-${DEBEZIUM_VERSION}-plugin.tar.gz"
    
    echo "✓ Extracted to directory"
    echo ""
    echo "Debezium Kafka-PostgreSQL connector ready at: $(pwd)/"
else
    echo "✗ Failed to download PostgreSQL connector"
    exit 1
fi
