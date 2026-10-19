# Home Server

Docker services on a Raspberry Pi. Each `*.yaml` is one Portainer stack, deployed from this repo; pushing to `main` redeploys them. Secrets are set as stack environment variables in Portainer, never committed.

## Stacks

| File | Services | UI | Stack env |
| --- | --- | --- | --- |
| `beszel-agent.yaml` | Beszel monitoring agent (CPU, memory, disks, S.M.A.R.T.) | – | `BESZEL_KEY`, `BESZEL_TOKEN` |
| `caddy.yaml` | Caddy reverse proxy: HTTPS on `*.pi.roots.ee` for the services below | :443 | `DO_AUTH_TOKEN` |
| `esphome.yaml` | ESPHome | :6052 | `USERNAME`, `PASSWORD` |
| `file-browser.yaml` | File Browser over `/mnt` | :8082 | `USERNAME`, `PASSWORD`, optional `UID`, `GID` |
| `home-assistant.yaml` | Home Assistant | :8123 | – |
| `homepage.yaml` | Homepage start page: a tile per service with up/down status, plus CPU, memory, temperature and disk use. Its config is written in this file. | via `https://pi.roots.ee` | – |
| `music-assistant.yaml` | Music Assistant | :8095 | – |
| `openthread.yaml` | OpenThread border router, Matter server, Thread credentials watcher, host sysctls | – | `THREAD_TONGLE_ID` |
| `plex.yaml` | Plex | :32400 | – |
| `portainer.yaml` | Portainer, applied by hand (see the file header) | :9443 | – |
| `zigbee2mqtt.yaml` | Zigbee2MQTT and its Mosquitto MQTT broker (localhost only, also used by HA) | :9123 | `ZIGBEE_TONGLE_ID` |

`*_TONGLE_ID` is the dongle's name under `/dev/serial/by-id/`. List the plugged-in dongles with:

```sh
ls -l /dev/serial/by-id/
```

Use the file name only, without the path, e.g. `usb-Nabu_Casa_SkyConnect_v1.0_<serial>-if00-port0`.

## HTTPS

Caddy serves the web UIs on subdomains of `pi.roots.ee`, using a Let's Encrypt wildcard certificate, plus a second certificate for the bare name:

| URL | Service |
| --- | --- |
| `https://pi.roots.ee` | Homepage, links to everything below |
| `https://ha.pi.roots.ee` | Home Assistant |
| `https://z2m.pi.roots.ee` | Zigbee2MQTT |
| `https://esphome.pi.roots.ee` | ESPHome |
| `https://music.pi.roots.ee` | Music Assistant |
| `https://files.pi.roots.ee` | File Browser |
| `https://portainer.pi.roots.ee` | Portainer |

Plex is not proxied; its apps already use HTTPS through Plex's own certificates.

The certificate is issued with a DNS challenge through the DigitalOcean API, so nothing on the Pi is opened to the internet. The names point at the Pi's LAN IP, so they only work at home.

The official Caddy image has no DNS plugins, so `caddy.yaml` builds its own image from the official `caddy:builder` and `caddy` images. To update Caddy, redeploy the stack with a rebuild.

One-time setup:

1. In the UniFi console, give the Pi a fixed IP (DHCP reservation).
2. In DigitalOcean, under Networking → Domains → `roots.ee`, add two `A` records with the Pi's LAN IP as the value: hostname `pi` and hostname `*.pi`.
3. In DigitalOcean, under API, create a token with custom scopes `domain: create, read, update, delete`. Caddy uses it only to add and remove the challenge's TXT records.
4. Tell Home Assistant to trust the proxy. Add this to its `configuration.yaml`, then restart HA:

   ```yaml
   http:
     use_x_forwarded_for: true
     trusted_proxies:
       - 127.0.0.1
       - ::1
   ```

   Without it, HA answers every proxied request with `400 Bad Request`.
5. Create the `caddy` stack in Portainer from `caddy.yaml` with `DO_AUTH_TOKEN` set. The first start takes a minute or two while the certificate is issued; follow it with `docker logs -f caddy`.
6. Open `https://ha.pi.roots.ee`. Then update the URLs the apps hand out:
   - HA → Settings → System → Network: set the local network URL to `https://ha.pi.roots.ee`.
   - Zigbee2MQTT `configuration.yaml`: set `frontend.url` to `https://z2m.pi.roots.ee`.

## Host scripts

These run on the Pi through systemd, not from Portainer, because they control Docker itself.

### Autoheal (`autoheal/`)

Docker only marks a container `unhealthy`; it never restarts it. Every minute, this restarts any container that has the label `autoheal: "true"` and is unhealthy. To include a service, give it a healthcheck and that label.

Install, or re-install after changing the files:

```sh
cd autoheal
sudo install -m 755 docker-autoheal.sh /usr/local/bin/docker-autoheal.sh
sudo install -m 644 docker-autoheal.service docker-autoheal.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-autoheal.timer
```

Restarts are logged in `journalctl -u docker-autoheal`.

### Backup (`backup/`)

Every night at 04:00, all Docker volumes are backed up to a restic repository at `/mnt/ssd1/Backup/docker`. Containers with SQLite databases are stopped for about a minute while it runs. Keeps 7 daily, 4 weekly and 6 monthly snapshots.

One-time setup:

```sh
sudo apt install -y restic
printf '%s' 'a-long-random-passphrase' | sudo tee /root/.restic-password
sudo chmod 600 /root/.restic-password
sudo restic init --repo /mnt/ssd1/Backup/docker
```

Keep a copy of the passphrase off the Pi; without it the backups can't be read.

Install, or re-install after changing the files:

```sh
cd backup
sudo install -m 755 docker-backup.sh /usr/local/bin/docker-backup.sh
sudo install -m 644 docker-backup.service docker-backup.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now docker-backup.timer
```

Run it now with `sudo systemctl start docker-backup`, check its log with `journalctl -u docker-backup`, and list snapshots with `sudo restic -r /mnt/ssd1/Backup/docker -p /root/.restic-password snapshots`.

### Firewall (`firewall/`)

An nftables firewall for traffic to the Pi itself, which is what the host-network services listen on. LAN devices can reach only the ports listed in `host-firewall.nft`; the Thread mesh, container networks, ICMP and multicast discovery are always allowed. Ports published by bridge-network containers (File Browser, Portainer, Zigbee2MQTT) and OTBR's Thread routing are not affected. It lives in its own table, so Docker's and OTBR's rules are left alone.

It ships in log-only mode: anything not allowed is logged but still let through.

Install, or re-install after changing the files:

```sh
cd firewall
sudo apt install -y nftables
sudo nft -c -f host-firewall.nft
sudo install -m 644 host-firewall.nft /etc/host-firewall.nft
sudo install -m 644 host-firewall.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now host-firewall
```

`nft -c` only checks the syntax. Don't enable `nftables.service`: Debian's `/etc/nftables.conf` starts with `flush ruleset`, which would wipe Docker's rules.

Rollout:

1. Run in log-only mode for a week and watch `journalctl -k -g host-firewall`. Each line is traffic that would be dropped.
2. Add ports for anything legitimate (e.g. an HA integration that receives callbacks) to `lan_tcp` / `lan_udp`, re-install, and run `sudo systemctl reload host-firewall`.
3. Once the log stays quiet, change the final `accept` to `drop`, re-install and reload.

If something breaks, `sudo systemctl stop host-firewall` removes the table at once. SSH (22) is always allowed.
