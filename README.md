# Hermes Kasm Workstation

A browser-accessible Ubuntu desktop based on Kasm's Ubuntu Noble desktop
image. Hermes Agent is installed manually during the image build, Hermes
WebUI runs in the same Ubuntu container, and a separate Tailscale container
provides tailnet access. Claude Code, Codex, OpenCode, Herder, Code Server,
`yt-dlp`/`youtube-dl`, ffmpeg, Monolith, Tesseract OCR, nano, git, jq, Python,
and Node.js are included.

This is a separate project from `hermes-workstation` and
`hermes-native-stack`. It does not include Fox, a Hindsight server, Buzz, or
Agent Vault. Hermes' Hindsight provider can connect to your existing service.

## Start

1. Copy `.env.example` to `.env` and set unique passwords for Kasm, Hermes
   WebUI, and Code Server. Optionally provide `TS_AUTHKEY`; otherwise Tailscale
   will show an interactive login URL.
2. Build and launch:

   ```sh
   docker compose up -d --build
   ```

3. Open the Kasm desktop at `https://localhost:6901` (Kasm's local TLS
   certificate is self-signed). Sign in as `kasm_user` using
   `KASM_VNC_PASSWORD`. Hermes WebUI is at `http://localhost:8788`; Code Server
   is at `http://localhost:8444`.
4. For Tailscale login without an auth key, follow the URL from:

   ```sh
   docker compose logs -f tailscale
   ```

   Tailnet access is through `<TS_HOSTNAME>:6901` for the desktop,
   `<TS_HOSTNAME>:8787` for Hermes WebUI, and `<TS_HOSTNAME>:8080` for Code
   Server. Use your tailnet access policy to limit who can reach the node.

The sidecar uses Tailscale kernel networking and `/dev/net/tun`. Linux Docker
is required for this mode. Docker Desktop on Windows/macOS can impose
TUN/device limitations. The default host ports (8788 and 8444) avoid conflicts
with the other Hermes projects in this workspace; change `WEBUI_PORT` or
`CODE_SERVER_PORT` in `.env` if needed.

## Deploy with Coolify

This stack is portable to Coolify as a **Git-based Docker Compose Application**.
Push this project folder to a Git repository with the Dockerfile,
`custom_startup.sh`, and `docker-compose.yml`, then point Coolify at the
Compose file. A pasted Compose definition alone is insufficient because
Coolify also needs the Docker build context files.

Add the variables from `.env.example` in Coolify's Environment Variables and
set fresh passwords and, optionally, a Tailscale auth key. The Compose file
keeps Kasm and Tailscale CPU/RAM limits, named persistent volumes, and
loopback-only host port bindings. `kasm-home`, `tailscale-state`, and
`workspace-data` persist Hermes configuration, Tailscale identity, and project
files across redeploys.

The Coolify deployment server must be Linux and allow Docker containers to use
`/dev/net/tun`, `NET_ADMIN`, and `NET_RAW`. Some hosted Docker environments
block these host capabilities; in that case, this kernel-mode sidecar cannot
start there. Reach the desktop, WebUI, and Code Server over the Tailscale
hostname and ports described above. The existing `127.0.0.1` port bindings
are intended for local access on the Docker host and do not publish these
services to the public internet.

The Kasm desktop listens over HTTPS with its own self-signed certificate.
Coolify's HTTP proxy/domain routing is optional; Tailscale is the configured
remote access path. If adding public domains later, configure and verify the
proxy route and access policy separately.

## Resource ceilings

The selected Standard profile caps the Kasm desktop at **4 CPU cores and
8 GiB RAM**, and Tailscale at **0.5 CPU and 256 MiB RAM**. Compose enforces
these container limits. Change `KASM_CPU_LIMIT`, `KASM_MEMORY_LIMIT`,
`TAILSCALE_CPU_LIMIT`, or `TAILSCALE_MEMORY_LIMIT` in `.env` to adjust them.

The persistent-data budget is **50 GiB** (`PERSISTENT_DATA_BUDGET`). Docker
Compose cannot enforce a portable per-volume disk quota. On Docker Desktop,
set the Docker disk image size in Settings → Resources → Advanced; this is a
global cap shared across Docker images and volumes. On Linux, apply a
filesystem project quota to a bind-mounted data directory or Docker's storage
filesystem for a hard disk cap.

## Hindsight and memory

No Hindsight service or local memory database is included. Hermes and the
WebUI run in the Kasm container, which shares the `hermes-kasm-shared` Docker
network with Tailscale. Connect an existing Hindsight container on this Docker
host to that network:

```sh
docker network connect hermes-kasm-shared <hindsight-container-name>
```

Set `HINDSIGHT_API_URL` in `.env` to the container's Docker DNS name and API
port, and set `HINDSIGHT_API_KEY` only if your Hindsight instance requires it.
Then restart the Kasm container:

```sh
docker compose up -d --force-recreate kasm-hermes
```

In the Ubuntu desktop terminal, install and configure Hermes' Hindsight
provider in external mode:

```sh
hermes plugins install hindsight --enable
hermes memory setup
```

Choose **Local External** and enter the service URL. To disable Hermes' own
local Markdown stores when using Hindsight, run:

```sh
hermes config set memory.memory_enabled false
hermes config set memory.user_profile_enabled false
```

To connect a separately composed Hindsight service reliably across its
recreations, declare `hermes-kasm-shared` as an external network in that
service's Compose file rather than relying on the one-time network command.

## Data and updates

The `kasm-home` volume stores the Kasm user profile, Hermes configuration and
sessions, WebUI state, and CLI logins. `workspace-data` is available in the
desktop, WebUI, Code Server, and CLI tools. `tailscale-state` keeps the
Tailscale device identity between restarts. Back up these volumes before
upgrades.

To update the Kasm base image, Hermes installer, WebUI checkout, and tools,
rebuild and recreate:

```sh
docker compose build --pull
docker compose up -d
```

The Hermes and WebUI versions are installed together at image-build time. This
tracks the versions available when you build; it does not perform unattended
updates inside a running desktop.

## How it is assembled

- `Dockerfile` extends `kasmweb/ubuntu-noble-desktop` and follows Kasm's
  default-profile and `custom_startup.sh` customization pattern.
- The Hermes installer and WebUI source are installed under the Kasm profile;
  WebUI uses Hermes' Python environment and agent modules.
- `custom_startup.sh` starts Hermes WebUI and Code Server for each desktop
  session. WebUI operates Hermes in-process; a separate Hermes gateway is not
  required for interactive WebUI chat.
- `docker-compose.yml` runs the Tailscale sidecar separately and shares its
  network namespace with the Kasm desktop. The Tailscale state persists in a
  named volume.
