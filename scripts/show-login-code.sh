#!/usr/bin/env bash
#
# Print the most recent Microsoft device-login URL + code from the
# minecraft-edu container's logs. Useful on first start, or whenever
# silent token refresh fails and the server prompts to sign in again.
#
# Usage:  scripts/show-login-code.sh [container-name]
#
set -euo pipefail

container="${1:-minecraft-edu}"

if ! docker inspect "$container" >/dev/null 2>&1; then
    echo "Container '$container' not found. Start it first: docker compose up -d" >&2
    exit 1
fi

# Server prints e.g.:
#   To sign in, use a web browser to open the page https://...
#   ...and enter the code XXXXXXXX to authenticate.
match="$(
    docker logs --tail 500 "$container" 2>&1 \
    | grep -Ei 'To sign in|enter the code' \
    | tail -2 || true
)"

if [[ -z "$match" ]]; then
    echo "No pending sign-in prompt found in the last 500 log lines."
    echo "If the server already authenticated, ./data/edu_server_session.json"
    echo "exists and no further action is needed."
    exit 0
fi

echo "$match"
