ARG KASM_IMAGE=kasmweb/ubuntu-noble-desktop:1.18.0@sha256:6e9274c5881bd2b5863cbaef754433be4d0a832d871a1fe52c995cb26f823501
FROM ${KASM_IMAGE}

USER root
ENV HOME=/home/kasm-default-profile \
    STARTUPDIR=/dockerstartup \
    DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Karachi \
    PATH=/home/kasm-user/.local/bin:/home/kasm-default-profile/.local/bin:/usr/local/bin:/usr/bin:/bin
WORKDIR /home/kasm-default-profile

# Desktop and developer utilities. The CLIs are installed globally so they
# remain available to the Kasm desktop user rather than only to root.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq nano ffmpeg tesseract-ocr yt-dlp \
      python3 python3-venv python3-pip pipx xz-utils \
      dbus-x11 procps util-linux \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/yt-dlp /usr/local/bin/youtube-dl

# Install the supported Node.js 24 LTS line; Ubuntu Noble's default Node 18
# does not satisfy current Claude Code CLI requirements.
ARG MONOLITH_VERSION=2.10.1
ARG HERMES_COMMIT=3d304a112b99b9cd56799d3b9f0ba50095fdda8c
RUN set -eu; \
    curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/nodesource_setup.sh; \
    bash /tmp/nodesource_setup.sh; \
    apt-get update; \
    apt-get install -y --no-install-recommends nodejs; \
    rm -rf /var/lib/apt/lists/* /tmp/nodesource_setup.sh; \
    node --version; \
    npm --version

RUN npm install --global @anthropic-ai/claude-code @openai/codex opencode-ai

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh \
    && UV_TOOL_DIR=/opt/uv-tools UV_TOOL_BIN_DIR=/usr/local/bin \
       uv tool install git+https://github.com/cleonhp88/herder.git

RUN set -eu; \
    case "$(dpkg --print-architecture)" in \
      amd64) monolith_arch=x86_64 ;; \
      arm64) monolith_arch=aarch64 ;; \
      *) echo "Unsupported architecture for Monolith" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/Y2Z/monolith/releases/download/v${MONOLITH_VERSION}/monolith-gnu-linux-${monolith_arch}" \
      -o /usr/local/bin/monolith; \
    chmod 0755 /usr/local/bin/monolith

# Install Hermes Agent into Kasm's default profile so it is copied into each
# user's persistent desktop profile on first start.
RUN mkdir -p "$HOME" && chown -R 1000:0 "$HOME" \
    && "$STARTUPDIR/set_user_permission.sh" "$HOME"
USER 1000
RUN curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --commit "$HERMES_COMMIT"
RUN git clone --depth 1 https://github.com/nesquena/hermes-webui.git \
       "$HOME/.local/share/hermes-webui" \
    && hermes_python="$(find "$HOME/.hermes/installs" -path '*/venv/bin/python' -print -quit)" \
    && test -n "$hermes_python" \
    && uv pip install --python "$hermes_python" \
       -r "$HOME/.local/share/hermes-webui/requirements.txt"

# Restore the Kasm image contract after customization.
USER root
RUN mkdir -p /home/kasm-user /workspace \
    && chown -R 1000:0 /home/kasm-user /workspace

COPY --chmod=755 custom_startup.sh /dockerstartup/custom_startup.sh
COPY --chmod=755 kasm-user-init.sh /usr/local/sbin/kasm-user-init
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/usr/local \
    && mkdir -p /home/kasm-default-profile/.local/share/code-server \
    && chown -R 1000:0 /home/kasm-default-profile/.local

ENV HOME=/home/kasm-user \
    HERMES_HOME=/home/kasm-default-profile/.hermes \
    HERMES_WEBUI_AGENT_DIR=/home/kasm-default-profile/.hermes/hermes-agent \
    HERMES_WEBUI_STATE_DIR=/home/kasm-user/.hermes/webui \
    HERMES_WEBUI_HOST=0.0.0.0 \
    HERMES_WEBUI_PORT=8787 \
    HERMES_WEBUI_DEFAULT_WORKSPACE=/workspace
WORKDIR /home/kasm-user
USER root
ENTRYPOINT ["/usr/local/sbin/kasm-user-init"]
