# Karl's Home Assistant

A separate Raspberry Pi 5 (hostname `ha`) on Karl's network, at `192.168.68.61` on Wi-Fi (`wlan0`; `eth0` is unplugged). Each `*.yaml` here is one Portainer stack deployed from this repo; secrets and dongle names are Portainer stack environment variables.

| File | Portainer stack | What | Address | Stack env |
| --- | --- | --- | --- | --- |
| `home-assistant.yaml` | 12 | Home Assistant | `http://ha.local:8123` | – |
| `matter-server.yaml` | 11 | Matter server and the Thread credentials watcher | localhost only | – |
| `zigbee2mqtt.yaml` | 10 | Zigbee2MQTT and its Mosquitto broker (localhost only) | `http://ha.local:9123` | `ZIGBEE_TONGLE_ID` |

`ZIGBEE_TONGLE_ID` is the dongle's file name in `ls -l /dev/serial/by-id/`, without the path. The coordinator is a TI CC2531 on Z-Stack Home 1.2, which has no coordinator backup: replacing it means re-pairing every device.

Data lives in bind mounts, not Docker volumes: `/home/pi/homeassistant`, `/home/pi/zigbee2mqtt/data`, `/home/pi/mosquitto.conf`, `/docker/matter-server/data`.

`bash check.sh` on the Pi is a read-only health check.

## Setup outside this repo

**Portainer** runs from `/home/pi/portainer-compose.yaml`. Port `8000` is only for Edge agents and can be removed from that file; the UI is `https://ha.local:9443`.

**Thread.** Karl's Pi has no border router of its own; the Aqara M100 and an Apple device route to the Thread mesh over Wi-Fi. The Pi must accept their route advertisements, or every Thread Matter device is unreachable. `/etc/sysctl.d/99-matter-thread.conf` must contain:

```
net.ipv6.conf.wlan0.accept_ra=2
net.ipv6.conf.wlan0.accept_ra_rt_info_max_plen=64
```

Check: `ip -6 route | grep 'proto ra'` shows an `fd..::/64` route via the border routers.

**Home Assistant** needs Thread credentials from the iOS companion app (Settings → Companion app → Troubleshooting → Sync Thread credentials). `matter-thread-credentials` hands HA's preferred Thread network to the Matter server.

**Zigbee2MQTT** (`/home/pi/zigbee2mqtt/data/configuration.yaml`): `frontend.port: 9123`, and set `frontend.auth_token`, since the UI is reachable from the whole LAN.

## Host scripts

Installed on the Pi with systemd. Copy the repo's `autoheal/` and `karl/backup/` folders, plus `backup/docker-backup.timer`, to the Pi, and run from there.

```sh
# autoheal/ (shared with the main server)
sudo install -m 755 docker-autoheal.sh /usr/local/bin/
sudo install -m 644 docker-autoheal.service docker-autoheal.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now docker-autoheal.timer

# karl/backup/ (Karl's own script; the timer is the main server's)
sudo install -m 755 docker-backup.sh /usr/local/bin/
sudo install -m 644 docker-backup.service docker-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now docker-backup.timer
```

**Autoheal:** every minute, restarts containers that are `unhealthy` and labelled `autoheal: "true"`. Log: `journalctl -u docker-autoheal`.

**Backup:** nightly at 04:00, the folders above plus Portainer's data to restic at `/var/backups/restic` (7 daily, 4 weekly, 6 monthly). Home Assistant, Zigbee2MQTT and the Matter server stop for about a minute. The repository is on the same NVMe as the data, so copy it off the Pi for protection against disk failure. One-time setup; keep the passphrase off the Pi too:

```sh
sudo apt install -y restic
printf '%s' 'a-long-random-passphrase' | sudo tee /root/.restic-password
sudo chmod 600 /root/.restic-password
sudo restic init --repo /var/backups/restic
```

Run now: `sudo systemctl start docker-backup`. Log: `journalctl -u docker-backup`.
