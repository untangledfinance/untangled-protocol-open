#!/bin/bash

IMAGE_NAME="slither-analyzer-local"

# Compile smart contracts
npm run compile

# Remove to rebuild
if docker images | awk '{print $1}' | grep -q "^$IMAGE_NAME$"; then
    echo "Image $IMAGE_NAME is already exists"
    docker rmi "$IMAGE_NAME:latest"
fi

# Build Docker image
DOCKER_CLI_HINTS=false docker build --no-cache -t $IMAGE_NAME -f Dockerfiles/slither.Dockerfile .

# Run Docker with cleanup option
docker run -it --rm $IMAGE_NAME .

# Clean up
yes | docker image prune
yes | docker container prune
