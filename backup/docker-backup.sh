#!/usr/bin/env bash
#
# Nightly backup of all Docker volumes into a restic repository on /mnt/ssd1.
#
# Installed on the host, not deployed by Portainer -- it has to stop containers, so it must not depend on Docker being healthy:
#   sudo install -m 755 docker-backup.sh /usr/local/bin/docker-backup.sh
#   sudo install -m 644 docker-backup.{service,timer} /etc/systemd/system/
#   sudo systemctl daemon-reload && sudo systemctl enable --now docker-backup.timer
#
# One-time setup:
#   sudo apt install -y restic
#   printf '%s' 'a-long-random-passphrase' | sudo tee /root/.restic-password
#   sudo chmod 600 /root/.restic-password
#   sudo restic init --repo /mnt/ssd1/Backup/docker
#
# Keep a copy of that passphrase somewhere off this machine. Without it the repository is unreadable, and a backup you cannot decrypt is not a backup.

set -euo pipefail

export RESTIC_REPOSITORY="/mnt/ssd1/Backup/docker"
export RESTIC_PASSWORD_FILE="/root/.restic-password"

VOLUMES="/var/lib/docker/volumes"

# Containers holding SQLite databases. Copying those live can capture a torn write that only shows up when you try to restore, so they are stopped for the duration -- roughly a minute.
STOP=(home-assistant plex zigbee2mqtt matter-server music-assistant)

stopped=()

start_stopped() {
    # ${a[@]+...} rather than ${a[@]:-}: the latter yields one empty name when nothing was stopped, and `docker start ""` fails.
    for name in ${stopped[@]+"${stopped[@]}"}; do
        docker start "$name" >/dev/null || echo "WARNING: failed to start $name" >&2
    done
    stopped=()
}

# Bring containers back even if restic fails or the unit is killed.
trap start_stopped EXIT

for name in "${STOP[@]}"; do
    if [ -n "$(docker ps -q -f "name=^${name}$")" ]; then
        # The default 10 s is too short for HA to flush its recorder; Docker then kills it mid-write, which is what stopping it was meant to avoid.
        docker stop -t 60 "$name" >/dev/null
        stopped+=("$name")
    fi
done

# The ESPHome build tree and Plex's cache are large and fully regenerated.
restic backup "$VOLUMES" \
    --tag docker-volumes \
    --exclude "$VOLUMES/backingFsBlockDev" \
    --exclude "$VOLUMES/metadata.db" \
    --exclude "$VOLUMES/esphome/_data/.esphome/build" \
    --exclude "$VOLUMES/esphome/_data/.esphome/platformio" \
    --exclude "$VOLUMES/plex/_data/Library/Application Support/Plex Media Server/Cache"

start_stopped
trap - EXIT

restic forget --tag docker-volumes \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 6 \
    --prune

# Cheap integrity check: verifies structure every run and 5% of the actual data.
restic check --read-data-subset=5%
