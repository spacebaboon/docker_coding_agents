# Base: Official Playwright image with browsers pre-installed
FROM mcr.microsoft.com/playwright:v1.61.1-noble

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Claude Code's background self-updater is left ENABLED. Previously it was
# disabled because the global install lived in a root-owned prefix, so the
# updater failed partway and left a stale ~/.claude/scheduled_tasks.lock
# ("Another instance is currently performing an update"). We now install Claude
# Code per-user into /home/claude/.npm-global (a user-owned prefix, see below)
# and put that bin dir first on PATH, so the updater can write successfully and
# the running `claude` is the updated one. The container keeps itself current
# without bumping a version on every release; a rebuild resets to whatever
# @latest resolved to at build time. To block updates entirely, set
# DISABLE_UPDATES=1 (stops `claude update`/`claude install` too).

# Newer git than Noble's 2.43, so `git worktree add --relative-paths` works in the
# container too - worktrees created on either side then resolve on both (host paths
# /Users/... and container paths /workspace/... differ, relative links bridge them).
RUN apt-get update \
    && apt-get install -y --no-install-recommends software-properties-common \
    && add-apt-repository -y ppa:git-core/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 (Playwright image has 18, we want newer for Claude Code)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Playwright MCP, Chrome DevTools MCP, Codex CLI, Gemini CLI, HumanLayer,
# and TS/Python language tooling globally (root prefix). Claude Code is NOT here -
# it is installed per-user further down (after USER claude) so its self-updater
# can write to a user-owned prefix instead of this root-owned one.
RUN npm install -g \
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
    && apt-get install -y lsof procps unzip micro curl less vim make git-crypt bash-completion sudo gettext-base openssl ripgrep jq fd-find tree wget bat git-delta \
    && rm -rf /var/lib/apt/lists/* \
    # Ubuntu ships these under alternate binary names; add the expected ones
    && ln -sf "$(which fdfind)" /usr/local/bin/fd \
    && ln -sf "$(which batcat)" /usr/local/bin/bat

# Python toolchain for backend work — the Playwright base image is
# Node-only. python-is-python3 puts `python` on PATH alongside `python3`.
# Note: Ubuntu Noble marks the system Python as externally managed (PEP 668),
# so prefer uv (below) for installs rather than `pip install` into the system.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 python3-venv python3-pip python-is-python3 \
    && rm -rf /var/lib/apt/lists/*

# uv (Astral) — copied from the official image: fast, multi-arch, reproducible,
# no install script. Provides `uv` and `uvx`; uv can also manage Python versions
# itself via `uv python install`.
COPY --from=ghcr.io/astral-sh/uv:0.11.17 /uv /uvx /usr/local/bin/

# Install Docker CLI (for docker-in-docker via socket mount)
RUN curl -fsSL https://get.docker.com | sh

# Install AWS CLI v2 (official installer — supports both x86_64 and aarch64)
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# Install yq (mikefarah, Go) — single release binary, arch-aware
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" \
        -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

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

# Token-aware gh wrapper on PATH (shadows /usr/bin/gh) so the read-write/read-only
# token is selected by working tree in EVERY shell context - not just interactive
# shells, where a shell function would be (see gh-wrapper.sh).
COPY gh-wrapper.sh /usr/local/bin/gh
RUN chmod 0755 /usr/local/bin/gh

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

# Put the user-owned npm prefix and ~/.local/bin FIRST on PATH. This is what makes
# `claude update` actually take effect: the updater installs into ~/.npm-global,
# and because that bin dir precedes /usr/bin, the updated binary is the one that
# runs (no stale system copy shadowing it).
ENV NPM_CONFIG_PREFIX=/home/claude/.npm-global
ENV PATH=/home/claude/.npm-global/bin:/home/claude/.local/bin:$PATH
RUN mkdir -p /home/claude/.npm-global

# Install Claude Code per-user, into the user-owned prefix set above, so the
# background self-updater can write to it. @latest pulls the newest at build time;
# the updater keeps it current thereafter. (Opus 4.8 needs >= 2.1.154.)
RUN npm install -g @anthropic-ai/claude-code@latest

# Install Bun as the claude user (will go to /home/claude/.bun)
RUN curl -fsSL https://bun.sh/install | bash

# Install uv (Astral) as the claude user — installs to ~/.local/bin
RUN curl -fsSL https://astral.sh/uv/install.sh | sh

# Create config directories
RUN mkdir -p /home/claude/.claude
RUN mkdir -p /home/claude/.config/micro

# Set micro colorscheme to a light theme
RUN echo '{"colorscheme": "bubblegum"}' > /home/claude/.config/micro/settings.json

# Configure MCP servers for Claude Code.
# These go in ~/.claude.json (user scope). ~/.claude.json is a *sibling* of the
# ~/.claude directory, which the claude-config named volume mounts over, so the
# baked file is not shadowed. IMPORTANT: this only works while CLAUDE_CONFIG_DIR
# is unset - setting it (e.g. to ~/.claude) redirects the main config to
# $CLAUDE_CONFIG_DIR/.config.json inside the volume, which shadows this file and
# makes claude.json a no-op. See the note in docker-compose.yml.
# Servers (see claude.json for definitions):
#   playwright, chrome-devtools : local stdio (npx)
#   atlassian, figma, locize    : remote OAuth; authenticate once with /mcp
# GitHub is not an MCP server here - use the gh CLI (token-aware by directory) to keep
# session context lean. No secrets live in this file (the remote servers use OAuth), so
# it is safe to commit. NOTE: this is baked into the image, so a container
# recreate resets ~/.claude.json to these definitions; treat claude.json as the
# source of truth and re-run /mcp auth for the OAuth servers if needed.
COPY --chown=claude:claude claude.json /home/claude/.claude.json

# Baked, directory-aware git config (the host ~/.gitconfig is no longer mounted).
# Identity plus token-based HTTPS auth: read-only token by default, read-write token
# inside the read-write project tree, and an SSH->HTTPS rewrite so token auth applies
# to SSH-style remotes. gitconfig is git-ignored per-dev (copy from gitconfig.example);
# gitconfig-ds is the committed read-write override (its token comes from the env).
COPY --chown=claude:claude gitconfig /home/claude/.gitconfig
COPY --chown=claude:claude gitconfig-ds /home/claude/.gitconfig-ds

WORKDIR /workspace

# Keep container alive for VS Code attach
CMD ["sleep", "infinity"]