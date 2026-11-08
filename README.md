# Home Server

Docker services on a Raspberry Pi (`192.168.1.2`). Each `*.yaml` is one Portainer stack deployed from this repo; pushing to `main` redeploys them. Secrets are Portainer stack environment variables, never committed.

## Services

| File | What | Address | Stack env |
| --- | --- | --- | --- |
| `beszel-agent.yaml` | Beszel monitoring agent (CPU, memory, disks, S.M.A.R.T.) | – | `BESZEL_KEY`, `BESZEL_TOKEN` |
| `caddy.yaml` | Reverse proxy: HTTPS for the addresses in this table | – | `DO_AUTH_TOKEN` |
| `esphome.yaml` | ESPHome | `https://esphome.pi.roots.ee` | `USERNAME`, `PASSWORD` |
| `file-browser.yaml` | File Browser over `/mnt` | `https://files.pi.roots.ee` | `USERNAME`, `PASSWORD`, optional `UID`, `GID` |
| `home-assistant.yaml` | Home Assistant | `https://ha.pi.roots.ee` | – |
| `homepage.yaml` | Start page linking everything, with system stats | `https://pi.roots.ee` | – |
| `music-assistant.yaml` | Music Assistant | `https://music.pi.roots.ee` | – |
| `openthread.yaml` | Thread border router, Matter server, Thread credentials watcher, host sysctls | – | `THREAD_TONGLE_ID` |
| `plex.yaml` | Plex; apps connect to 32400 directly | `https://plex.pi.roots.ee` | – |
| `portainer.yaml` | Portainer; applied by hand, see the file header | `https://portainer.pi.roots.ee` | – |
| `zigbee2mqtt.yaml` | Zigbee2MQTT and its Mosquitto broker (localhost only, also used by HA) | `https://z2m.pi.roots.ee` | `ZIGBEE_TONGLE_ID` |

`*_TONGLE_ID` is the dongle's file name in `ls -l /dev/serial/by-id/`, without the path.

## Access

Caddy serves every web UI over HTTPS (Let's Encrypt, DNS challenge via DigitalOcean). The names resolve to the Pi's LAN IP, so they work only at home.

The firewall blocks direct access to the proxied UIs; only Plex's 32400 stays open for its apps. If Caddy breaks:

- `sudo systemctl stop host-firewall` reopens all ports (start it again afterwards), or
- tunnel one UI: `ssh -L 8123:127.0.0.1:8123 pi@192.168.1.2`, then `http://localhost:8123`.

## Setup outside this repo

**UniFi**
- DHCP reservation `192.168.1.2` for the Pi, so DNS stays valid.

**DigitalOcean** (Domains → `roots.ee`)
- `A` records `pi` and `*.pi` → `192.168.1.2`. Not a `CNAME`: it breaks the certificate challenge.
- API token, scope `domain` (create, read, update, delete), as `DO_AUTH_TOKEN` on the `caddy` stack. Caddy uses it for the challenge records.

**Home Assistant** (Settings → System → Network)
- **Trust X-Forwarded-For** on, **Trusted proxies** `127.0.0.1/32` and `::1/128`. Otherwise HA rejects Caddy with `400`. Change it directly on `:8123`, not through Caddy, since HA asks to confirm after the restart.
- **Local network URL** `https://ha.pi.roots.ee`, so links and speakers use the reachable address.

**Zigbee2MQTT** (Settings → Frontend)
- **url** `https://z2m.pi.roots.ee`, so links point to the reachable address. Leave **host** empty: Docker's port forwarding needs it listening on all interfaces.

**Caddy**
- Built on the Pi to include the DigitalOcean plugin. To update: `docker pull caddy:builder && docker pull caddy:latest`, then redeploy.

## Host scripts

Installed on the Pi with systemd, since they control Docker. Run from the script's folder; repeat after a change.

```sh
# autoheal/
sudo install -m 755 docker-autoheal.sh /usr/local/bin/
sudo install -m 644 docker-autoheal.service docker-autoheal.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now docker-autoheal.timer

# backup/
sudo install -m 755 docker-backup.sh /usr/local/bin/
sudo install -m 644 docker-backup.service docker-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now docker-backup.timer

# firewall/
sudo apt install -y nftables
sudo nft -c -f host-firewall.nft
sudo install -m 644 host-firewall.nft /etc/
sudo install -m 644 host-firewall.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now host-firewall
```

**Autoheal:** every minute, restarts containers that are `unhealthy` and labelled `autoheal: "true"`. Docker only marks them. Log: `journalctl -u docker-autoheal`.

**Backup:** nightly at 04:00, all Docker volumes to restic at `/mnt/ssd1/Backup/docker` (7 daily, 4 weekly, 6 monthly). SQLite containers stop for about a minute. One-time setup; keep the passphrase off the Pi too:

```sh
sudo apt install -y restic
printf '%s' 'a-long-random-passphrase' | sudo tee /root/.restic-password
sudo chmod 600 /root/.restic-password
sudo restic init --repo /mnt/ssd1/Backup/docker
```

Run now: `sudo systemctl start docker-backup`. Log: `journalctl -u docker-backup`.

**Firewall:** own nftables table, so Docker's and OTBR's rules stay intact. Don't enable `nftables.service`: its default config wipes them. Log-only for now, except the proxied UIs: watch `journalctl -k -g host-firewall` for a week, open what's legitimate, then change the final `accept` to `drop`. After editing: `sudo systemctl reload host-firewall`.
