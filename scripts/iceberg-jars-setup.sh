#!/bin/bash

# Exit on any error
set -e

# Set the target directory for the Kafka Connect JAR and connector files
TARGET_DIR="$(pwd)/custom-plugins/iceberg-connector-kafka"

echo "========================================================="
echo "Starting Iceberg Kafka Connect build process..."
echo "Target directory: $TARGET_DIR"
echo "========================================================="

# Create target directory if it doesn't exist
# mkdir -p "$TARGET_DIR"
# cd "$TARGET_DIR"

# Clean up any existing containers and artifacts
echo "Cleaning up existing artifacts..."
docker rm -f iceberg-build 2>/dev/null || true
rm -rf iceberg *.jar *.zip lib

# Create and run build container to download gradle (builder), iceberg repo and store jars
echo "Creating build container and building Iceberg..."
docker run -it --name iceberg-build -v "$TARGET_DIR":/workspace eclipse-temurin:17-jdk bash -c '
    cd /workspace &&
    echo "Installing dependencies..." &&
    apt-get update &&
    apt-get install -y git unzip wget &&
    echo "Installing Gradle..." &&
    wget https://services.gradle.org/distributions/gradle-8.14.3-bin.zip &&
    unzip gradle-8.14.3-bin.zip -d /opt &&
    export PATH=/opt/gradle-8.14.3/bin:$PATH &&
    echo "Cloning Iceberg repository..." &&
    git clone --depth 1 https://github.com/apache/iceberg.git &&
    cd iceberg &&
    echo "Building Iceberg Kafka connector..." &&
    ./gradlew -x test -x integrationTest clean build &&
    echo "Copying Kafka Connect ZIP files..." &&
    mkdir -p /workspace/lib &&
    cp kafka-connect/kafka-connect-runtime/build/distributions/iceberg-kafka-connect-runtime-*.zip /workspace/ 2>/dev/null || true &&
    echo "Extracting connector files..." &&
    cd /workspace &&
    for zip in iceberg-kafka-connect-runtime-*.zip; do
        if [ -f "$zip" ]; then
            unzip -o "$zip"
            rm "$zip"
        fi
    done &&
    echo "Cleaning up..." &&
    rm -rf iceberg gradle-*.zip
'

# Check if build was successful
if [ $? -eq 0 ]; then
    echo "========================================================="
    echo "Build completed successfully!"
    echo "Cleaning up build container..."
    docker rm iceberg-build

    echo "Available artifacts in $TARGET_DIR:"
    ls -la "$TARGET_DIR"
    echo -e "\nConnector library files in $TARGET_DIR/lib:"
    ls -la "$TARGET_DIR/lib"

    echo "========================================================="
    echo "Setup completed! Connector files are available in:"
    echo "$TARGET_DIR"
else
    echo "========================================================="
    echo "Build failed!"
    docker rm iceberg-build
    exit 1
fi