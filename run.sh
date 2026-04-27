#!/usr/bin/env bash
# run.sh — pull the latest remote image and run the experiment once.
#
# Usage:
#   sh ./run.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is not installed or not in PATH." >&2
    exit 1
fi

echo "Pulling latest remote image from GHCR..."
docker compose -f "${COMPOSE_FILE}" pull

echo "Running experiment container..."
docker compose -f "${COMPOSE_FILE}" run --rm experiment
