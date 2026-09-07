#!/usr/bin/env bash
set -euo pipefail
CONFIG_FILE="$1"
URL="$(jq -r '.url' "$CONFIG_FILE")"
exec cog "$URL"