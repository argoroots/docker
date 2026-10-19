#!/usr/bin/env bash
#
# Restarts containers labelled autoheal=true once Docker reports them unhealthy; Docker itself only marks them, restart policies act on exit, not on health.
#
# Installed on the host, not deployed by Portainer, so no third-party image needs the Docker socket:
#   sudo install -m 755 docker-autoheal.sh /usr/local/bin/docker-autoheal.sh
#   sudo install -m 644 docker-autoheal.{service,timer} /etc/systemd/system/
#   sudo systemctl daemon-reload && sudo systemctl enable --now docker-autoheal.timer

set -euo pipefail

docker ps --filter label=autoheal=true --filter health=unhealthy --format '{{.Names}}' |
while read -r name; do
    echo "restarting unhealthy $name"
    # 60 s rather than Docker's 10 s: HA needs that long to flush its recorder.
    docker restart -t 60 "$name" >/dev/null || echo "WARNING: failed to restart $name" >&2
done
