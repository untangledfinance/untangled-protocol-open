#!/bin/bash

OUTPUT_PATH="./analysis"
IMAGE_NAME="slither-analyzer-local"

if ! docker images | awk '{print $1}' | grep -q "^$IMAGE_NAME$"; then
    echo "Image does not exist"
    # Build Slither image
    DOCKER_CLI_HINTS=false docker build -t $IMAGE_NAME -f Dockerfiles/slither.Dockerfile .
else
    echo "Image $IMAGE_NAME is already exists, ignore building image."
fi

# Create the output directory if it doesn't exist
mkdir -p "$OUTPUT_PATH"

# Run Docker with cleanup option
docker run -it --rm $IMAGE_NAME .

# Clean up
yes | docker image prune
yes | docker container prune
