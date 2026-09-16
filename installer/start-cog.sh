#!/usr/bin/env bash
set -euo pipefail

PLAYER_URL="http://127.0.0.1:3000/player" 

echo "Waiting for signage application at ${PLAYER_URL}..." 

until curl \ 
    --output /dev/null \ 
    --silent \ 
    --fail \ 
    --max-time 2 \ 
    "${PLAYER_URL}" 
do 
    sleep 1 
done 

echo "Signage application is ready." 
echo "Starting Cog..." 

exec /usr/bin/cog "${PLAYER_URL}"