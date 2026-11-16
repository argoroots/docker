#!/usr/bin/env bash
# Nightly backup of Karl's Pi into a local restic repository. Karl's stacks use bind mounts, not named volumes, so this backs up those folders instead of /var/lib/docker/volumes. Installed on the host, as it has to stop containers; setup and install in karl/README.md.

set -euo pipefail

# Same disk as the data: this protects against a bad update or a broken database, not against the NVMe dying. Copy the repository elsewhere for that.
export RESTIC_REPOSITORY="/var/backups/restic"
export RESTIC_PASSWORD_FILE="/root/.restic-password"

PATHS=(
    /home/pi/homeassistant
    /home/pi/zigbee2mqtt/data
    /home/pi/mosquitto.conf
    /home/pi/portainer-compose.yaml
    /docker/matter-server/data
    # Portainer's database holds the stack definitions and their env vars (ZIGBEE_TONGLE_ID).
    /var/lib/docker/volumes/portainer_data
    /etc/sysctl.d/99-matter-thread.conf
)

# Containers holding SQLite databases or rewriting their state files. Copying those live can capture a torn write that only shows up when you try to restore, so they are stopped for the duration -- roughly a minute.
STOP=(home-assistant zigbee2mqtt matter-server)

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

# HA's own backups/ would be stored twice; logs and the TTS cache are regenerated.
restic backup "${PATHS[@]}" \
    --tag karl \
    --exclude /home/pi/homeassistant/backups \
    --exclude /home/pi/homeassistant/tts \
    --exclude '/home/pi/homeassistant/home-assistant.log*' \
    --exclude /home/pi/zigbee2mqtt/data/log

start_stopped
trap - EXIT

restic forget --tag karl \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 6 \
    --prune

# Cheap integrity check: verifies structure every run and 5% of the actual data.
restic check --read-data-subset=5%
