# castova-docker

Public Docker distribution for [Castova](https://castova.net) — self-hosted, high-availability audio streaming control panel.

## Quick Install

```bash
curl -sSL https://get.castova.net | bash
```

Supported OS: Ubuntu 22.04+, Debian 12+

## Manual Install

```bash
git clone https://github.com/castova-io/castova-docker.git /opt/castova
cd /opt/castova
bash install.sh
```

## What gets installed

| Container | Purpose |
|-----------|--------|
| `panel` | Castova web UI + API |
| `postgres` | PostgreSQL 16 database |
| `redis` | Redis 7 cache |
| `mosquitto` | MQTT broker (port 1883) |
| `caddy` | Reverse proxy with automatic HTTPS |
| `livekit` | WebRTC SFU for Castova Studio |
| `studio-bridge` | Bridges Studio audio to Liquidsoap |
| `coturn` | TURN server for NAT traversal |

## Updating

```bash
cd /opt/castova
git pull
docker compose pull
docker compose up -d --force-recreate
```

## Documentation

- [Getting Started](https://castova.net/docs/getting-started)
- [Full Documentation](https://castova.net/docs)
- [Support](https://castova.net/support)

## Source Code

Castova is source-available. The application source is at [castova-io/castova-io](https://github.com/castova-io/castova-io).
