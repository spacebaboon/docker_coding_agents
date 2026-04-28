# Base: Official Playwright image with browsers pre-installed
FROM mcr.microsoft.com/playwright:v1.58.2-noble

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install Node.js 22 (Playwright image has 18, we want newer for Claude Code)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code, Playwright MCP, Chrome DevTools MCP, Codex CLI, Gemini CLI, and HumanLayer
RUN npm install -g \
    @anthropic-ai/claude-code@latest \
    @playwright/mcp@latest \
    chrome-devtools-mcp@latest \
    @openai/codex@latest \
    @google/gemini-cli@latest \
    humanlayer@latest

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

# Configure MCP servers for Claude Code:
# playwright: browser automation via accessibility snapshots
# chrome-devtools: performance profiling, network inspection, console debugging
RUN echo '{\n\
  "mcpServers": {\n\
    "playwright": {\n\
      "command": "npx",\n\
      "args": [\n\
        "@playwright/mcp",\n\
        "--browser", "chromium",\n\
        "--headless",\n\
        "--no-sandbox"\n\
      ]\n\
    },\n\
    "chrome-devtools": {\n\
      "command": "npx",\n\
      "args": [\n\
        "chrome-devtools-mcp",\n\
        "--headless",\n\
        "--isolated",\n\
        "--executable-path", "/usr/local/bin/chromium-browser",\n\
        "--no-usage-statistics"\n\
      ]\n\
    }\n\
  }\n\
}' > /home/claude/.claude/.config.json

WORKDIR /workspace

# Keep container alive for VS Code attach
CMD ["sleep", "infinity"]