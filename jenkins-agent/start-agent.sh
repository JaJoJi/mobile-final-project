#!/bin/bash

set -e

echo "Starting Docker daemon..."

dockerd > /var/log/dockerd.log 2>&1 &

echo "Waiting for Docker daemon..."

until docker info >/dev/null 2>&1; do
    sleep 1
done

echo "Docker daemon is ready."

echo "Starting Jenkins agent..."

exec /usr/local/bin/jenkins-agent "$@"