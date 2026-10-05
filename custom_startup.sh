#!/usr/bin/env bash
set -euo pipefail

export HOME=/home/kasm-user
export HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
export HERMES_WEBUI_AGENT_DIR="${HERMES_WEBUI_AGENT_DIR:-$HERMES_HOME/hermes-agent}"
if [ -z "${HERMES_WEBUI_PYTHON:-}" ]; then
  HERMES_WEBUI_PYTHON="$(find "$HERMES_HOME" -type f -path '*/bin/python' -print -quit)"
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
