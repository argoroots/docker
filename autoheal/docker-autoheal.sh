#!/usr/bin/env bash
# Restarts containers labelled autoheal=true once Docker reports them unhealthy. Installed on the host; see README.

set -euo pipefail

docker ps --filter label=autoheal=true --filter health=unhealthy --format '{{.Names}}' |
while read -r name; do
    echo "restarting unhealthy $name"
    # 60 s rather than Docker's 10 s: HA needs that long to flush its recorder.
    docker restart -t 60 "$name" >/dev/null || echo "WARNING: failed to restart $name" >&2
done
