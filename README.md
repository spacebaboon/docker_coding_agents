# docker_coding_agents

A Docker container for safely running agentic coding CLIs — **Claude Code**, **OpenAI Codex**, and **Gemini** — alongside MCP servers for **Playwright** and **Chrome DevTools**.

**TL;DR** run Claude Code (et al) in YOLO mode to remove the constand hand-holding of approving commands, but don't let it nuke your home directory.

The goal is to give an agent broad freedom to read, write, and execute inside a sandboxed Linux environment without giving it the same freedoms on your host machine. The container runs as a non-root user, drops all Linux capabilities except a minimal set, has a memory cap, and only sees the project directories you explicitly mount in.

**Top tip** Use this with slash commands from

## What's included

- **Coding agents**: `claude`, `codex`, `gemini`, plus `humanlayer`
- **MCP servers** preconfigured for Claude Code:
  - `playwright` — browser automation via accessibility snapshots
  - `chrome-devtools` — performance profiling, network inspection, console debugging
- **Runtimes**: Node.js 22, Bun, Playwright's bundled Chromium
- **Tooling**: Docker CLI (via socket mount), AWS CLI v2, git, git-crypt, micro, vim, less, make, bash-completion
- **Quality of life**: colored prompt with git branch, prompt-history helpers (`np` / `ep` / `lp` / `rp`), a `dangerclaude` alias for `claude --dangerously-skip-permissions`

## Safety model

- **Non-root user** (`claude`) inside the container. (Sudo is passwordless so install scripts work — the real isolation comes from the layers below, not from blocking sudo.)
- **`cap_drop: ALL`** with only `CHOWN`, `SETUID`, `SETGID` added back.
- **Bridge networking** — no host network access.
- **16 GB memory cap**.
- **No host filesystem access** beyond the directories mounted in `docker-compose.yml`.

## Performance

- package.json mounted by configuration as container-only storage, which is many times faster than on shared disk between host and container, and gives near native speeds, especially on full unit test runs.

## Quick start

```bash
# 1. Configure where your projects live on the host
cp .env.example .env
$EDITOR .env                            # set PROJECTS_DIR

# 2. (Optional) set up per-project node_modules volumes
cp docker-compose.override.yml.example docker-compose.override.yml
$EDITOR docker-compose.override.yml     # see "node_modules speedup" below

# 3. Build and start
docker compose up -d --build

# 4. Drop into a shell
docker exec -it claude-pw bash

# Inside the container:
cd /workspace/your-project
dangerclaude          # or: codex, gemini
```

## Configuration files

### `.env` — host paths

Created from `.env.example`. Sets host-side paths used by `docker-compose.yml`.

| Variable       | Default       | Purpose                                                                                                           |
| -------------- | ------------- | ----------------------------------------------------------------------------------------------------------------- |
| `PROJECTS_DIR` | `../projects` | Host directory mounted at `/workspace` inside the container. Can be absolute or relative to `docker-compose.yml`. |

The `.env` file is git-ignored, so each user keeps their own.

### `docker-compose.override.yml` — node_modules speedup

Created from `docker-compose.override.yml.example`. Docker Compose auto-merges this with `docker-compose.yml` on every `up` / `build`.

**Why it matters**: bind-mounting `node_modules` from macOS or Windows into a Linux container is **painfully slow**. The cross-OS filesystem layer pays a per-file tax, and `node_modules` is hundreds of thousands of small files. Installs that take 20 seconds natively can take 10+ minutes through a bind mount, and runtime tools (`tsc`, `vite`, `next`) crawl.

The fix: shadow each project's `node_modules` directory with a **named Docker volume**, which lives on the container's native ext4 filesystem.

```yaml
services:
  claude:
    volumes:
      - my-project-node-modules:/workspace/my-project/node_modules

volumes:
  my-project-node-modules:
```

After adding an entry, run `npm install` (or `bun install`) once inside the container to populate the volume. The trade-off: `node_modules` is no longer visible from the host, so editor features like "go to definition" into a dependency only work from inside the container (e.g. via VS Code's "Attach to Running Container").

**If you also run the project natively on the host** (e.g. `npm run dev` on macOS as well as inside the container), you need to `npm install` (or `yarn` / `bun install`) **on both sides**. The named volume and the host's `node_modules` directory are separate filesystems — installing in one does not populate the other, and lockfile changes need to be re-applied wherever you run code. A common gotcha: bumping a dep on the host, then hitting "module not found" inside the container until you rerun the install there too.

This file is git-ignored, so each user maintains their own list of projects.

## What's mounted

| Host                    | Container                       | Notes                                        |
| ----------------------- | ------------------------------- | -------------------------------------------- |
| `${PROJECTS_DIR}`       | `/workspace`                    | Your projects directory                      |
| `~/.gitconfig`          | `/home/claude/.gitconfig`       | read-only                                    |
| `~/.ssh`                | `/home/claude/.ssh`             | read-only — for git over SSH                 |
| `~/.claude/commands`    | `/home/claude/.claude/commands` | read-only — humanlayer slash commands        |
| `~/thoughts`            | `/home/claude/thoughts`         | persistent agent notes                       |
| `~/prompts`             | `/home/claude/prompts`          | prompt history (used by `np`/`ep`/`lp`/`rp`) |
| `/var/run/docker.sock`  | `/var/run/docker.sock`          | docker-in-docker via host daemon             |
| `claude-config` (named) | `/home/claude/.claude`          | persists Claude settings/history             |

## Writing longer prompts (`np` / `ep` / `lp` / `rp`)

For prompts longer than a single line, typing into the Claude Code TUI is awkward — newlines, paste, and editing are all clumsy. These aliases let you draft a prompt in `micro` (a real editor) and then reference it from the agent.

| Alias | Action                                                                |
| ----- | --------------------------------------------------------------------- |
| `np`  | **new prompt** — opens a fresh timestamped `.md` file in `micro` and symlinks it as `latest.md` |
| `ep`  | **edit prompt** — reopen the latest prompt to tweak it                |
| `lp`  | **list prompt** — print the latest prompt to the terminal             |
| `rp`  | **recent prompts** — show the last 20 prompt files, newest first      |

Prompts live in `~/prompts/` inside the container, which is mounted to `~/prompts/` on the host — so they survive container rebuilds and are searchable from either side.

Typical flow:

```bash
np                              # write your prompt, save & quit micro
claude                          # (or dangerclaude / codex / gemini)
> @~/prompts/latest.md          # Claude Code reads the file as the prompt
```

The `@` prefix is Claude Code's file-reference syntax. Iterate by hitting `ep` to edit, then re-referencing `@~/prompts/latest.md` in a new turn. `rp` is useful for grabbing an older prompt by timestamp when you want to reuse or fork it.

## Common commands

```bash
docker compose up -d --build         # build & start
docker compose down                  # stop & remove
docker exec -it claude-pw bash       # shell in
docker compose logs -f claude        # tail logs
docker compose build --no-cache      # force a clean rebuild after Dockerfile changes
```

## Layout

```
.
├── Dockerfile                              # image definition
├── docker-compose.yml                      # base service config (committed)
├── docker-compose.override.yml.example     # template for per-user node_modules volumes
├── .env.example                            # template for host paths
├── aliases.sh                              # shell prompt + helpers, baked into the image
└── .claude/                                # tool permissions for the host-side Claude Code
```
