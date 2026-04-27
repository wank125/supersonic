#!/usr/bin/env bash

# Multi-stage Docker build: builds everything inside the container
# No local Java/Maven/Node.js required

VERSION=${1:-1.0.0-SNAPSHOT}

echo "Building Docker image: supersonicbi/supersonic:${VERSION}"
echo "This will build the project inside Docker (may take 10-20 minutes on first run)..."

docker build \
  --build-arg SUPERSONIC_VERSION=${VERSION} \
  -t supersonicbi/supersonic:${VERSION} \
  -f docker/Dockerfile \
  .

if [ $? -ne 0 ]; then
  echo "Docker build failed."
  exit 1
fi

echo "Docker image supersonicbi/supersonic:${VERSION} built successfully."
