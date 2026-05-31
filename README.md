# docker-openchamber

Self-hostable [OpenChamber](https://github.com/openchamber/openchamber) (OpenCode web UI) for ARM64/AMD64.

[![GitHub](https://img.shields.io/badge/github-docker--openchamber-blue?logo=github)](https://github.com/maksimstojkovic/docker-openchamber)

## Overview

This container image builds and publishes multi-arch (`linux/amd64`, `linux/arm64`) Docker images for the latest OpenChamber release to `ghcr.io/maksimstojkovic/docker-openchamber`.

- **Base image:** `debian:trixie-slim` with s6-overlay
- **Port:** `3000` (OpenChamber default)
- **Authentication:** Optional UI password via `UI_PASSWORD`
- **Bundled tooling:** Nano, Vim, jq, ripgrep, fd-find, ImageMagick, graphviz, python3-matplotlib, python3-pil
- **Auto-updates:** Automatic upstream version tracking via GitHub Actions

## Prerequisites

- Docker & Docker Compose
- [SWAG](https://docs.linuxserver.io/general/swag) (or another reverse proxy) for HTTPS access

## Quick Start

```bash
git clone https://github.com/maksimstojkovic/docker-openchamber.git
cd docker-openchamber
mkdir -p data/openchamber/{config,ssh,workspace}
cp .env.example .env
# Edit .env to match your preferences
docker compose up -d
```

## SWAG Proxy Setup

Copy the sample configuration to your SWAG container:

```bash
cp swag/openchamber.subdomain.conf.sample /path/to/swag/nginx/proxy-confs/openchamber.subdomain.conf
```

Restart SWAG to apply the changes.

## UI Password Setup

Set `UI_PASSWORD` in your `.env` file:

```bash
UI_PASSWORD=your_secure_password_here
```

## External OpenCode Server Setup

To use an external OpenCode instance instead of the bundled one:

```bash
OPENCODE_EXTERNAL=true
OPENCODE_HOSTNAME=opencode
OPENCODE_PORT=4096
```

## Updating

Pull the latest image and recreate the container:

```bash
docker compose pull
docker compose up -d
```

## Tags

| Tag | Description |
|-----|-------------|
| `latest` | Latest stable release |
| `1.11` | Latest patch release in the 1.11.x series |
| `1.11.7` | Specific release version |
| `sha-xxx` | Specific commit build |

## Building Locally

```bash
docker compose -f docker-compose.dev.yml up -d --build
```

## License

MIT
