# Base: Official Playwright image with browsers pre-installed
FROM mcr.microsoft.com/playwright:v1.60.0-noble

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Disable Claude Code's background self-updater. In a container the global
# install lives in a root-owned prefix, so the autoupdater fails partway and
# leaves a stale ~/.claude/scheduled_tasks.lock ("Another instance is currently
# performing an update"). Updates here happen by rebuilding the image instead.
# Note: this stops the background check only; `claude update`/`claude install`
# still work. Use DISABLE_UPDATES=1 instead to block those too.
ENV DISABLE_AUTOUPDATER=1

# Install Node.js 22 (Playwright image has 18, we want newer for Claude Code)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code, Playwright MCP, Chrome DevTools MCP, Codex CLI, Gemini CLI, and HumanLayer
# @latest pulls the newest version at build time. Opus 4.8 needs Claude Code
# >= 2.1.154, so rebuild this image to pick it up (or pin a version here).
RUN npm install -g \
    @anthropic-ai/claude-code@latest \
    @playwright/mcp@latest \
    chrome-devtools-mcp@latest \
    @openai/codex@latest \
    @google/gemini-cli@latest \
    humanlayer@latest \
    typescript@latest \
    typescript-language-server@latest \
    pyright@latest


# pnpm via Corepack
RUN corepack enable && corepack prepare pnpm@11.5.0 --activate

# Install useful CLI tools including micro editor
RUN apt-get update \
    && apt-get install -y lsof procps unzip micro curl less vim make git-crypt bash-completion sudo gettext-base openssl \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI (for docker-in-docker via socket mount)
RUN curl -fsSL https://get.docker.com | sh

# Install AWS CLI v2 (official installer — supports both x86_64 and aarch64)
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
    && mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Create a stable symlink to the Playwright-bundled Chromium binary
# so chrome-devtools-mcp (Puppeteer-based) can find it via --executable-path
RUN ln -sf $(find /ms-playwright -name chrome -path '*/chrome-linux/*' -type f | head -1) \
    /usr/local/bin/chromium-browser

# Create non-root user for safety, with passwordless sudo for install scripts
RUN useradd -m -s /bin/bash claude \
    && echo 'claude ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/claude \
    && chmod 440 /etc/sudoers.d/claude

# Copy aliases file and source it from .bashrc (works for all shell sessions)
COPY aliases.sh /home/claude/.aliases.sh
RUN chown claude:claude /home/claude/.aliases.sh \
    && echo '' >> /home/claude/.bashrc \
    && echo '# Source custom aliases' >> /home/claude/.bashrc \
    && echo '[ -f ~/.aliases.sh ] && . ~/.aliases.sh' >> /home/claude/.bashrc \
    && echo '# Enable bash completion (git branches, etc.)' >> /home/claude/.bashrc \
    && echo '[ -f /etc/bash_completion ] && . /etc/bash_completion' >> /home/claude/.bashrc

USER claude

ENV NPM_CONFIG_PREFIX=/home/claude/.npm-global
ENV PATH=$PATH:/home/claude/.npm-global/bin
RUN mkdir -p /home/claude/.npm-global

# Install Bun as the claude user (will go to /home/claude/.bun)
RUN curl -fsSL https://bun.sh/install | bash

# Create config directories
RUN mkdir -p /home/claude/.claude
RUN mkdir -p /home/claude/.config/micro

# Set micro colorscheme to a light theme
RUN echo '{"colorscheme": "bubblegum"}' > /home/claude/.config/micro/settings.json

# Configure MCP servers for Claude Code.
# These go in ~/.claude.json (user scope), NOT ~/.claude/.config.json — the latter
# is not a path Claude Code reads, and ~/.claude is mounted over by the
# claude-config named volume anyway. ~/.claude.json is a *sibling* of that
# directory, so it is not shadowed.
# Servers (see claude.json for definitions):
#   playwright, chrome-devtools : local stdio (npx)
#   github                      : stdio via the mounted Docker socket; PAT passed
#                                 through GITHUB_PERSONAL_ACCESS_TOKEN, read-only
#   atlassian, figma, locize    : remote OAuth; authenticate once with /mcp
# No secrets live in this file (PAT is injected at runtime, the rest use OAuth),
# so it is safe to commit. NOTE: this is baked into the image, so a container
# recreate resets ~/.claude.json to these definitions; treat claude.json as the
# source of truth and re-run /mcp auth for the OAuth servers if needed.
COPY --chown=claude:claude claude.json /home/claude/.claude.json

WORKDIR /workspace

# Keep container alive for VS Code attach
CMD ["sleep", "infinity"]