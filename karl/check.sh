#!/usr/bin/env bash
# Read-only health check for Karl's Pi. Changes nothing. Run: bash check.sh

set -o pipefail

echo "== CPUs / RAM (cpus limit 2.0 needs >= 2 cores)"
nproc; free -h | awk 'NR<=2'

echo "== Docker server version (start_interval needs >= 25)"
docker version --format '{{.Server.Version}}'

echo "== Containers on the zigbee2mqtt stack network (only mosquitto + zigbee2mqtt may be here)"
docker network inspect zigbee2mqtt_default --format '{{range .Containers}}{{.Name}} {{end}}' 2>&1

echo "== Leftovers (old iot network, anonymous volumes): should be empty"
docker network ls --filter name='^iot$' --format '{{.Name}}'
docker volume ls --format '{{.Name}}' | grep -E '^[0-9a-f]{64}$'

echo "== mosquitto.conf"
cat /home/pi/mosquitto.conf

echo "== MQTT clients seen by Mosquitto (192.168.x = LAN device that will lose access)"
docker logs mosquitto 2>&1 | grep -o 'New client connected from [0-9a-f.:]*' | awk '{print $5}' | sed 's/:[0-9]*$//' | sort | uniq -c

echo "== Zigbee2MQTT frontend (port must be 9123; auth_token should be set)"
sudo grep -A6 '^frontend' /home/pi/zigbee2mqtt/data/configuration.yaml | sed -E 's/(auth_token:).*/\1 <set>/' || echo "no frontend section"

echo "== Home Assistant http: (ssl_certificate breaks the healthcheck)"
grep -A6 '^http:' /home/pi/homeassistant/configuration.yaml || echo "no http section"

echo "== Home Assistant Matter URL (must be localhost or 127.0.0.1)"
sudo grep -o '"url": *"ws://[^"]*"' /home/pi/homeassistant/.storage/core.config_entries || echo "no Matter integration"

echo "== Matter data present"
sudo ls /docker/matter-server/data

echo "== Thread route (needs a fd..::/64 'proto ra' route via the border routers)"
ip -6 route | grep 'proto ra' || echo "no Thread route"
sysctl net.ipv6.conf.wlan0.accept_ra net.ipv6.conf.wlan0.accept_ra_rt_info_max_plen

echo "== Host timers (autoheal, backup)"
systemctl list-timers --all --no-pager | grep -E 'docker-(autoheal|backup)' || echo "not installed"

echo "== Current status"
docker ps --format '{{.Names}}\t{{.Status}}'
