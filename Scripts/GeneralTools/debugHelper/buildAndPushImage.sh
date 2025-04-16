#!/bin/bash

# Check if required arguments are provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <tag> [registry_client]"
    exit 1
fi

REGISTRY="sfbrdevhelmweacr.azurecre.io"
IMAGE_NAME="sf-debug-helper"
TAG="$1"
REGISTRY_CLIENT="${2:-docker}"  # Use docker by default, allow override via parameter

IMAGE_TAG="$REGISTRY/$IMAGE_NAME:$TAG"

echo "Building image using $REGISTRY_CLIENT: $IMAGE_TAG"

# Build the image
$REGISTRY_CLIENT build -t "$IMAGE_TAG" .

# Check if build was successful
if [ $? -ne 0 ]; then
    echo "$REGISTRY_CLIENT build failed!"
    exit 1
fi

echo "Pushing image using $REGISTRY_CLIENT: $IMAGE_TAG"

# Push the image to the registry
$REGISTRY_CLIENT push "$IMAGE_TAG"

# Check if push was successful
if [ $? -ne 0 ]; then
    echo "$REGISTRY_CLIENT push failed!"
    exit 1
fi

echo "Image successfully pushed: $IMAGE_TAG"