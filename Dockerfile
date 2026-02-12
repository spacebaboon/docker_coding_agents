# Base: Official Playwright image with browsers pre-installed
FROM mcr.microsoft.com/playwright:v1.58.2-noble

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install Node.js 22 (Playwright image has 18, we want newer for Claude Code)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code, Playwright MCP, Chrome DevTools MCP, Codex CLI, and Gemini CLI
RUN npm install -g \
    @anthropic-ai/claude-code@latest \
    @playwright/mcp@latest \
    chrome-devtools-mcp@latest \
    @openai/codex@latest \
    @google/gemini-cli@latest

# Install useful CLI tools
RUN apt-get update \
    && apt-get install -y lsof procps \
    && rm -rf /var/lib/apt/lists/*

# Create a stable symlink to the Playwright-bundled Chromium binary
# so chrome-devtools-mcp (Puppeteer-based) can find it via --executable-path
RUN ln -sf $(find /ms-playwright -name chrome -path '*/chrome-linux/*' -type f | head -1) \
    /usr/local/bin/chromium-browser

# Create non-root user for safety
RUN useradd -m -s /bin/bash claude

# Copy aliases file and source it from .bashrc (works for all shell sessions)
COPY aliases.sh /home/claude/.aliases.sh
RUN chown claude:claude /home/claude/.aliases.sh \
    && echo '' >> /home/claude/.bashrc \
    && echo '# Source custom aliases' >> /home/claude/.bashrc \
    && echo '[ -f ~/.aliases.sh ] && . ~/.aliases.sh' >> /home/claude/.bashrc

USER claude

# Create config directories
RUN mkdir -p /home/claude/.claude

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
}' > /home/claude/.claude.json

WORKDIR /workspace

# Keep container alive for VS Code attach
CMD ["sleep", "infinity"]
