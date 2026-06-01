# docker_coding_agents

A Docker container for safely running agentic coding CLIs — **Claude Code**, **OpenAI Codex**, and **Gemini** — alongside MCP servers for **Playwright**, **Chrome DevTools**, **GitHub**, **Jira/Confluence**, **Figma**, and **Locize**.

**TL;DR** run Claude Code (et al) in YOLO mode to remove the constant hand-holding of approving commands, but don't let it nuke your home directory or GitHub main.

The goal is to give an agent broad freedom to read, write, and execute inside a sandboxed Linux environment without giving it the same freedoms on your host machine. The container runs as a non-root user, drops all Linux capabilities except a minimal set, has a memory cap, and only sees the project directories you explicitly mount in.

**Top tip** Use this with slash commands from humanlayer, mounted read-only at `~/.claude/commands`.

## What's included

- **Coding agents**: `claude`, `codex`, `gemini`, plus `humanlayer`
- **MCP servers** preconfigured for Claude Code (see [MCP servers](#mcp-servers-claudejson)):
  - `playwright` — browser automation via accessibility snapshots
  - `chrome-devtools` — performance profiling, network inspection, console debugging
  - `github` — repositories, issues, PRs, build status (read-only, via the mounted Docker socket)
  - `atlassian` — Jira and Confluence (remote, OAuth)
  - `figma` — design context (remote, OAuth)
  - `locize` — translation strings (remote, OAuth)
- **Runtimes**: Node.js 22, Bun, pnpm (via Corepack), Playwright's bundled Chromium
- **Tooling**: Docker CLI (via socket mount), GitHub CLI (`gh`), AWS CLI v2, git, git-crypt, TypeScript & Python (Pyright) language servers, micro, vim, less, make, bash-completion
- **Quality of life**: colored prompt with git branch, prompt-history helpers (`np` / `ep` / `lp` / `rp`), a `dangerclaude` alias for `claude --dangerously-skip-permissions`

## Safety model

- **Non-root user** (`claude`) inside the container. (Sudo is passwordless so install scripts work — the real isolation comes from the layers below, not from blocking sudo.)
- **`cap_drop: ALL`** with only `CHOWN`, `SETUID`, `SETGID` added back.
- **Bridge networking** — no host network access.
- **16 GB memory cap**.
- **No host filesystem access** beyond the directories mounted in `docker-compose.yml`.

Note: the Docker socket is mounted so the agent (and the `github` MCP server) can use docker-in-docker. This is convenient but does give the container control of the host Docker daemon, so it is not a hard security boundary — treat it as part of the trust you extend to the tools you run.

## Performance

- `node_modules` mounted by configuration as container-only storage, which is many times faster than on shared disk between host and container, and gives near native speeds, especially on full unit test runs.

## Quick start

```bash
# 1. Configure host paths and your GitHub token
cp .env.example .env
$EDITOR .env                            # set PROJECTS_DIR and GITHUB_PERSONAL_ACCESS_TOKEN

# 2. Create your working copies of the git-ignored config files
cp CLAUDE.md.example CLAUDE.md          # user-level agent memory (must exist before `up`)
cp claude.json.example claude.json      # MCP server definitions (must exist before `build`)
$EDITOR CLAUDE.md                       # tweak to taste

# 3. (Optional) set up per-project node_modules volumes
cp docker-compose.override.yml.example docker-compose.override.yml
$EDITOR docker-compose.override.yml     # see "node_modules speedup" below

# 4. Build and start
docker compose up -d --build

# 5. Drop into a shell
docker exec -it claude-pw bash

# Inside the container:
cd /workspace/your-project
dangerclaude          # or: codex, gemini

# 6. One-time: authenticate the remote MCP servers
#    Run `claude`, type `/mcp`, and complete the OAuth login for
#    atlassian, figma, and locize. Logins persist in the volume.
```

## Configuration files

### `.env` — host paths and secrets

Created from `.env.example`. Sets host-side values used by `docker-compose.yml`.

| Variable                       | Default       | Purpose                                                                                                                                                                                     |
| ------------------------------ | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PROJECTS_DIR`                 | `../projects` | Host directory mounted at `/workspace` inside the container. Can be absolute or relative to `docker-compose.yml`.                                                                           |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | _(none)_      | Passed through to the container for the `github` MCP server. A **read-only fine-grained** PAT is recommended (matches the read-only GitHub policy). Set it here or export it in your shell. |

The `.env` file is git-ignored, so each user keeps their own.

### `CLAUDE.md` — user-level agent memory

A user-level `CLAUDE.md` is bind-mounted read-only into the container at `~/.claude/CLAUDE.md`, giving every project in the container a shared baseline of instructions. It is bind-mounted (not baked into the image) because the `claude-config` named volume shadows `~/.claude/`, so a copy baked there would not take effect.

```bash
cp CLAUDE.md.example CLAUDE.md
$EDITOR CLAUDE.md
```

`CLAUDE.md` is git-ignored (your personal copy); `CLAUDE.md.example` is the committed baseline. **The file must exist before `docker compose up`**, or Docker silently creates an empty _directory_ at the mount path.

### MCP servers (`claude.json`)

MCP servers are defined as config-as-code in `claude.json`, copied into the image at `~/.claude.json` — the user-scope location Claude Code actually reads. (`~/.claude/` is shadowed by the `claude-config` volume, so MCP config placed there does not take effect.) No secrets live in it: the GitHub PAT is injected at runtime via `GITHUB_PERSONAL_ACCESS_TOKEN`, and the remote servers use OAuth.

`claude.json` is git-ignored (your working copy); `claude.json.example` is the committed baseline — copy it on first setup (`cp claude.json.example claude.json`). **It must exist before you build**, since the Dockerfile copies it into the image.

- **`playwright`**, **`chrome-devtools`** — local stdio servers; work out of the box.
- **`github`** — runs the official `ghcr.io/github/github-mcp-server` as a stdio server over the mounted Docker socket, authenticated with `GITHUB_PERSONAL_ACCESS_TOKEN` and started read-only. The first GitHub call pulls that image once.
- **`atlassian`** (Jira/Confluence), **`figma`**, **`locize`** — remote servers using OAuth. Authenticate once per `claude-config` volume: run `claude`, type `/mcp`, and complete the browser login for each. Credentials persist in the volume, so you don't repeat this on rebuild.

Check status any time with `claude mcp list`. Because `~/.claude.json` is baked into the image, recreating the container resets it to whatever `claude.json` held at build time — edit `claude.json` and rebuild to add servers, rather than relying on runtime `claude mcp add`.

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

After adding an entry, run `pnpm install` (or `npm` / `bun install`) once inside the container to populate the volume. The trade-off: `node_modules` is no longer visible from the host, so editor features like "go to definition" into a dependency only work from inside the container (e.g. via VS Code's "Attach to Running Container").

**If you also run the project natively on the host** (e.g. `pnpm dev` on macOS as well as inside the container), you need to install **on both sides**. The named volume and the host's `node_modules` directory are separate filesystems — installing in one does not populate the other, and lockfile changes need to be re-applied wherever you run code. A common gotcha: bumping a dep on the host, then hitting "module not found" inside the container until you rerun the install there too.

This file is git-ignored, so each user maintains their own list of projects.

## What's mounted

| Host                    | Container                        | Notes                                        |
| ----------------------- | -------------------------------- | -------------------------------------------- |
| `${PROJECTS_DIR}`       | `/workspace`                     | Your projects directory                      |
| `./CLAUDE.md`           | `/home/claude/.claude/CLAUDE.md` | read-only — user-level agent memory          |
| `~/.gitconfig`          | `/home/claude/.gitconfig`        | read-only                                    |
| `~/.ssh`                | `/home/claude/.ssh`              | read-only — for git over SSH                 |
| `~/.claude/commands`    | `/home/claude/.claude/commands`  | read-only — humanlayer slash commands        |
| `~/thoughts`            | `/home/claude/thoughts`          | persistent agent notes                       |
| `~/prompts`             | `/home/claude/prompts`           | prompt history (used by `np`/`ep`/`lp`/`rp`) |
| `/var/run/docker.sock`  | `/var/run/docker.sock`           | docker-in-docker via host daemon             |
| `claude-config` (named) | `/home/claude/.claude`           | persists Claude settings/history/MCP logins  |

## Writing longer prompts (`np` / `ep` / `lp` / `rp`)

For prompts longer than a single line, typing into the Claude Code TUI is awkward — newlines, paste, and editing are all clumsy. These aliases let you draft a prompt in `micro` (a real editor) and then reference it from the agent.

| Alias | Action                                                                                          |
| ----- | ----------------------------------------------------------------------------------------------- |
| `np`  | **new prompt** — opens a fresh timestamped `.md` file in `micro` and symlinks it as `latest.md` |
| `ep`  | **edit prompt** — reopen the latest prompt to tweak it                                          |
| `lp`  | **list prompt** — print the latest prompt to the terminal                                       |
| `rp`  | **recent prompts** — show the last 20 prompt files, newest first                                |

Prompts live in `~/prompts/` inside the container, which is mounted to `~/prompts/` on the host — so they survive container rebuilds and are searchable from either side.

Typical flow:

```bash
np                              # write your prompt, save & quit micro
claude                          # (or dangerclaude / codex / gemini)
> @~/prompts/latest.md          # Claude Code reads the file as the prompt
```

The `@` prefix is Claude Code's file-reference syntax. Iterate by hitting `ep` to edit, then re-referencing `@~/prompts/latest.md` in a new turn. `rp` is useful for grabbing an older prompt by timestamp when you want to reuse or fork it.

## Updating

Claude Code's background auto-updater is **disabled** in the image (`DISABLE_AUTOUPDATER=1`), so it can't drift to a new version mid-task or leave a stale update lock. The installed version is whatever `@latest` resolved to at build time. To move to a newer Claude Code (or pick up a model like Opus 4.8, which needs a recent enough build), **rebuild the image**.

Docker layer caching can defeat this: the `npm install -g ... @latest` layer is cached, so if nothing above it changed you'll get the _same_ version back. Changing the base image or anything earlier in the Dockerfile busts the cache; otherwise force it:

```bash
docker compose build --no-cache          # or: --pull
docker compose up -d --force-recreate
docker compose exec claude claude --version
```

## Common commands

```bash
docker compose up -d --build                    # build & start
docker compose up -d --build --force-recreate   # rebuild + replace the container
                                                #   (needed for zombie-reaping init and baked-config changes)
docker compose down                             # stop & remove
docker exec -it claude-pw bash                  # shell in
docker compose logs -f claude                   # tail logs
docker compose build --no-cache                 # force a clean rebuild after Dockerfile changes
docker compose exec claude claude --version     # check the installed Claude Code version
```

If `claude` ever reports `Another instance is currently performing an update`, a previous update died and left a lock. Remove it (it lives in the persistent `claude-config` volume) and retry:

```bash
docker compose exec claude rm -f /home/claude/.claude/scheduled_tasks.lock
```

## Layout

```
.
├── Dockerfile                              # image definition
├── docker-compose.yml                      # base service config (committed)
├── docker-compose.override.yml.example     # template for per-user node_modules volumes
├── .env.example                            # template for host paths & secrets
├── claude.json.example                     # MCP server definitions template (committed)
├── claude.json                             # your MCP config (git-ignored, copied from the example)
├── CLAUDE.md.example                       # user-level agent memory template (committed)
├── CLAUDE.md                               # your personal agent memory (git-ignored, copied from the example)
├── aliases.sh                              # shell prompt + helpers, baked into the image
├── .gitignore
└── .claude/                                # tool permissions for the host-side Claude Code
```
