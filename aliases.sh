# Shell aliases for Claude Playwright container
# This file is sourced from .bashrc for all interactive shells

# ── Colors ────────────────────────────────────────────────────────────────────
export CLICOLOR=1
export LS_COLORS='di=1;34:ln=1;36:so=35:pi=33:ex=1;32:bd=1;33:cd=1;33:su=37;41:sg=30;43:tw=30;42:ow=34;42'
export GREP_COLORS='ms=01;31:mc=01;31:sl=:cx=:fn=35:ln=32:bn=32:se=36'

alias ls='ls --color=auto'
alias ll='ls -lart --color=auto'
alias la='ls -la --color=auto'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias diff='diff --color=auto'
alias ip='ip --color=auto'

# Colored man pages
export LESS_TERMCAP_mb=$'\e[1;31m'
export LESS_TERMCAP_md=$'\e[1;34m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;32m'

# Colored bash prompt: user@host in green, cwd in blue, git branch in yellow
# \w is trimmed to the last 2 path components via PROMPT_DIRTRIM.
PROMPT_DIRTRIM=2
__git_branch() {
  local b
  b=$(git branch --show-current 2>/dev/null) || return
  [ -z "$b" ] && return
  if [ ${#b} -gt 20 ]; then
    b="${b:0:20}…"
  fi
  printf ' (%s)' "$b"
}
PS1='\[\e[1;32m\]\u\[\e[0m\]:\[\e[1;34m\]\w\[\e[1;33m\]$(__git_branch)\[\e[0m\]\$ '

# General
alias ..='cd ..'

# Git
alias gits='git status'
alias gitd='git diff'
alias gitl='git log --oneline -20'

# GitHub CLI
# Pick the GitHub token by working tree: inside the read-write project tree
# (GH_RW_TREE) use the read-write token; everywhere else use the read-only token,
# the safe default. Mirrors the git credential setup in ~/.gitconfig. The GitHub
# MCP servers are configured separately (github-rw / github-ro in claude.json).
gh() {
  case "$PWD/" in
    "${GH_RW_TREE:-__no_rw_tree__}"/*) GH_TOKEN="$GH_TOKEN_RW" command gh "$@" ;;
    *) GH_TOKEN="$GH_TOKEN_RO" command gh "$@" ;;
  esac
}
alias gl='gh repo list'
alias gp='gh pr view --web'

# AI tools
alias dangerclaude='claude --dangerously-skip-permissions'

# ── Prompt helpers ────────────────────────────────────────────────────────────
# np  : new prompt  — open a timestamped file in micro, symlink as latest
# ep  : edit prompt — reopen latest prompt for tweaking
# lp  : list prompt — print latest prompt to terminal
# rp  : recent prompts — show last 20 prompt files by date
# Usage in Claude Code: @~/prompts/latest.md
# ─────────────────────────────────────────────────────────────────────────────
PROMPT_DIR=/home/claude/prompts

np() {
  mkdir -p "$PROMPT_DIR"
  local file="$PROMPT_DIR/$(date +%Y-%m-%d-%H%M%S).md"
  micro "$file"
  ln -sf "$file" "$PROMPT_DIR/latest.md"
}

ep() {
  micro "$PROMPT_DIR/latest.md"
}

lp() {
  cat "$PROMPT_DIR/latest.md"
}

rp() {
  ls -lt "$PROMPT_DIR"/*.md 2>/dev/null | head -20
}

# Create a git worktree as a sibling of the main checkout, named after the branch.
# Handles git-crypt key linking automatically. Needs bash or zsh.
# Usage: wt <branch-name> [--install]
wt() {
  local branch="$1"
  if [ -z "$branch" ]; then
    echo "usage: wt <branch-name> [--install]" >&2
    return 1
  fi

  # directory name = branch with any slashes flattened (slashes would nest dirs)
  local dirname="${branch//\//-}"

  # place it next to the MAIN checkout, wherever we are in the repo
  local toplevel parent target
  toplevel="$(git rev-parse --show-toplevel)" || return 1
  parent="$(dirname "$toplevel")"
  target="$parent/$dirname"

  if [ -e "$target" ]; then
    echo "wt: '$target' already exists" >&2
    return 1
  fi

  # create WITHOUT checking out, so git-crypt's smudge filter doesn't run
  # before we've linked the key into the new worktree's git dir
  if git show-ref --quiet --verify "refs/heads/$branch"; then
    git worktree add --no-checkout "$target" "$branch" || return 1
  else
    git worktree add --no-checkout "$target" -b "$branch" || return 1
  fi

  # link the git-crypt key (only if this repo uses git-crypt)
  local common_dir wt_gitdir
  common_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd)"   # absolute
  wt_gitdir="$(git -C "$target" rev-parse --absolute-git-dir)"
  if [ -d "$common_dir/git-crypt" ] && [ ! -e "$wt_gitdir/git-crypt" ]; then
    ln -s "$common_dir/git-crypt" "$wt_gitdir/git-crypt"
  fi

  # now populate the working tree — smudge can decrypt cleanly
  git -C "$target" reset --hard || return 1

  cd "$target" || return 1

  if [ "$2" = "--install" ]; then
    pnpm install
  else
    echo "worktree ready at $target — run 'pnpm install' for deps"
  fi
}
