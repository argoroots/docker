#!/usr/bin/env bash
# Read-only pre-deploy check for Karl's Pi. Changes nothing. Run: bash check.sh

echo "== CPUs / RAM (cpus limit 2.0 needs >= 2 cores)"
nproc; free -h | awk 'NR<=2'

echo "== Docker server version (start_interval needs >= 25)"
docker version --format '{{.Server.Version}}'

echo "== Containers on the iot network (only mosquitto + zigbee2mqtt may be here)"
docker network inspect iot --format '{{range .Containers}}{{.Name}} {{end}}' 2>&1

echo "== mosquitto.conf"
cat /home/pi/mosquitto.conf

echo "== MQTT clients seen by Mosquitto (192.168.x = LAN device that will lose access)"
docker logs mosquitto 2>&1 | grep -o 'New client connected from [0-9a-f.:]*' | awk '{print $5}' | sed 's/:[0-9]*$//' | sort | uniq -c

echo "== Zigbee2MQTT frontend"
grep -A4 '^frontend' /home/pi/zigbee2mqtt/data/configuration.yaml || echo "no frontend section (port 8080)"

echo "== Home Assistant http: (ssl_certificate breaks the healthcheck)"
grep -A6 '^http:' /home/pi/homeassistant/configuration.yaml || echo "no http section"

echo "== Home Assistant Matter URL (must be localhost or 127.0.0.1)"
sudo grep -o '"url": *"ws://[^"]*"' /home/pi/homeassistant/.storage/core.config_entries || echo "no Matter integration"

echo "== Matter data present"
ls /docker/matter-server/data

echo "== Current status"
docker ps --format '{{.Names}}\t{{.Status}}'
