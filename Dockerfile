# Cloudera ML runtime + Claude Code CLI → LiteLLM → AWS Bedrock
#
# This image routes Claude Code through a local LiteLLM proxy to Bedrock.
# LiteLLM is not strictly required: Claude Code has native Bedrock support
# (CLAUDE_CODE_USE_BEDROCK=1 + AWS credentials + ANTHROPIC_DEFAULT_*_MODEL).
# A slimmer image can omit the LiteLLM venv, proxy scripts, and Python deps
# below — see README "Alternative: native Bedrock (no LiteLLM)".
FROM --platform=linux/amd64 docker.repository.cloudera.com/cloudera/cdsw/ml-runtime-pbj-jupyterlab-python3.13-standard:2026.08.1-b5

# ── System dependencies (agent tooling) ────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        vim nano \
        tmux screen \
        curl wget less tree jq unzip zip \
        ripgrep fd-find bat \
        netcat-openbsd dnsutils iputils-ping \
        pciutils htop procps lsof strace \
        ssh-client rsync socat ca-certificates git \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# ── Node.js 20 (required by Claude Code) ─────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# ── Claude Code CLI ──────────────────────────────────────────────────────────
RUN npm install -g @anthropic-ai/claude-code \
    && command -v claude >/dev/null

# ── LiteLLM proxy (Anthropic API → AWS Bedrock) ────────────────────────────────
# Optional layer: remove this block (and bedrock-common.sh / profile hook) for
# direct Bedrock — Claude Code calls Bedrock Invoke API without a local proxy.
COPY requirements-litellm.txt /opt/bedrock-claude/requirements-litellm.txt
COPY scripts/verify-litellm-install.sh /opt/bedrock-claude/verify-litellm-install.sh
RUN chmod +x /opt/bedrock-claude/verify-litellm-install.sh && \
    python3 -m venv /opt/bedrock-claude/venv && \
    /opt/bedrock-claude/venv/bin/pip install --no-cache-dir --upgrade pip wheel packaging && \
    /opt/bedrock-claude/venv/bin/pip install --no-cache-dir -r /opt/bedrock-claude/requirements-litellm.txt && \
    SKIP_LITELLM_SMOKE=1 /opt/bedrock-claude/verify-litellm-install.sh /opt/bedrock-claude/venv

# ── ttyd: browser-based terminal (optional; CML may wire APP_PORT) ───────────
RUN TTYD_URL=$(curl -s https://api.github.com/repos/tsl0922/ttyd/releases/latest \
        | grep '"browser_download_url"' \
        | grep 'ttyd\.x86_64"' \
        | head -1 \
        | cut -d'"' -f4) && \
    curl -fsSL "$TTYD_URL" -o /usr/local/bin/ttyd && \
    chmod +x /usr/local/bin/ttyd

# ── Runtime directories ──────────────────────────────────────────────────────
RUN mkdir -p /home/cdsw/.claude/bedrock /opt/bedrock-claude/lib && \
    chown -R cdsw:cdsw /home/cdsw/.claude

COPY scripts/lib/bedrock-common.sh /opt/bedrock-claude/lib/bedrock-common.sh
COPY scripts/bedrock-runtime-startup.sh /etc/profile.d/claude-bedrock.sh
RUN chmod +x /etc/profile.d/claude-bedrock.sh /opt/bedrock-claude/lib/bedrock-common.sh && \
    echo '[ -f /etc/profile.d/claude-bedrock.sh ] && source /etc/profile.d/claude-bedrock.sh' \
        >> /etc/bash.bashrc

# ── Default environment (override in CML project / session settings) ─────────
ENV BEDROCK_HOME="/home/cdsw/.claude/bedrock" \
    BEDROCK_VENV_BIN="/opt/bedrock-claude/venv/bin" \
    BEDROCK_MODEL="" \
    AWS_ACCESS_KEY_ID="" \
    AWS_SECRET_ACCESS_KEY="" \
    AWS_REGION="" \
    BEDROCK_LITELLM_PORT="4000" \
    BEDROCK_MAX_OUTPUT_TOKENS="8192" \
    BEDROCK_MAX_INPUT_TOKENS="192000" \
    APP_PORT="8080"

EXPOSE 8080
WORKDIR /home/cdsw

ENV ML_RUNTIME_EDITION="Claude Code with AWS Bedrock"
LABEL com.cloudera.ml.runtime.edition=$ML_RUNTIME_EDITION
