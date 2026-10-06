#!/usr/bin/env bash
set -euo pipefail

export HOME=/home/kasm-user
export HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
export HERMES_WEBUI_AGENT_DIR="${HERMES_WEBUI_AGENT_DIR:-$HERMES_HOME/hermes-agent}"

# The Hermes checkout and managed runtime live in the writable hermes-runtime
# volume. Migrate only user configuration/state from the older Kasm home once;
# never copy its stale install metadata or managed tools over the current install.
legacy_hermes_home="$HOME/.hermes"
migration_marker="$HERMES_HOME/.kasm-user-home-migrated"
if [ "$legacy_hermes_home" != "$HERMES_HOME" ] && [ ! -e "$migration_marker" ]; then
  mkdir -p "$HERMES_HOME"
  for item in config.yaml .env auth.lock SOUL.md; do
    if [ -f "$legacy_hermes_home/$item" ]; then
      cp -f "$legacy_hermes_home/$item" "$HERMES_HOME/$item"
    fi
  done
  for item in memories sessions pairing skills cron backups hooks audio_cache image_cache; do
    if [ -d "$legacy_hermes_home/$item" ]; then
      mkdir -p "$HERMES_HOME/$item"
      cp -an "$legacy_hermes_home/$item/." "$HERMES_HOME/$item/"
    fi
  done
  touch "$migration_marker"
fi

if [ -z "${HERMES_WEBUI_PYTHON:-}" ]; then
  # The managed Hermes venv's python is usually a symlink into its Python tool,
  # so `find -type f` skips it and can select the dependency-free bootstrap Python.
  HERMES_WEBUI_PYTHON="$(find "$HERMES_HOME/installs" -path '*/venv/bin/python' -print -quit 2>/dev/null || true)"
  if [ -z "$HERMES_WEBUI_PYTHON" ]; then
    HERMES_WEBUI_PYTHON="$(find /home/kasm-default-profile/.hermes/installs -path '*/venv/bin/python' -print -quit 2>/dev/null || true)"
  fi
  if [ -z "$HERMES_WEBUI_PYTHON" ]; then
    HERMES_WEBUI_PYTHON="$(command -v python3 || true)"
  fi
  export HERMES_WEBUI_PYTHON
fi
export HERMES_WEBUI_STATE_DIR="${HERMES_WEBUI_STATE_DIR:-$HERMES_HOME/webui}"
export HERMES_WEBUI_HOST=0.0.0.0
export HERMES_WEBUI_PORT=8787
export HERMES_WEBUI_DEFAULT_WORKSPACE=/workspace

mkdir -p "$HERMES_HOME/logs" "$HERMES_WEBUI_STATE_DIR" \
  "$HOME/.config/code-server" "$HOME/.local/share/code-server" /workspace

webui_dir="$HOME/.local/share/hermes-webui"
if [ ! -d "$webui_dir" ]; then
  echo "Hermes WebUI checkout is missing from the Kasm profile" >&2
  exit 1
fi
if [ -z "$HERMES_WEBUI_PYTHON" ] || [ ! -x "$HERMES_WEBUI_PYTHON" ]; then
  echo "Hermes Python environment was not found under $HERMES_HOME" >&2
  exit 1
fi

if ! pgrep -f '[s]erver.py' >/dev/null 2>&1; then
  nohup "$HERMES_WEBUI_PYTHON" "$webui_dir/server.py" \
    >"$HERMES_HOME/logs/webui.log" 2>&1 </dev/null &
fi

node -e 'const fs = require("fs"); const p = JSON.stringify(process.env.CODE_SERVER_PASSWORD || ""); fs.writeFileSync(process.env.HOME + "/.config/code-server/config.yaml", `bind-addr: 0.0.0.0:8080\nauth: password\npassword: ${p}\ncert: false\n`, { mode: 0o600 });'
if ! pgrep -x code-server >/dev/null 2>&1; then
  nohup code-server --user-data-dir "$HOME/.local/share/code-server" \
    --extensions-dir "$HOME/.local/share/code-server/extensions" /workspace \
    >"$HERMES_HOME/logs/code-server.log" 2>&1 </dev/null &
fi
