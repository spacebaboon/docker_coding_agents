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
__git_branch() {
  git branch 2>/dev/null | sed -n 's/^\* \(.*\)/ (\1)/p'
}
PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[1;33m\]$(__git_branch)\[\e[0m\]\$ '

# General
alias ..='cd ..'

# Git
alias gits='git status'
alias gitd='git diff'
alias gitl='git log --oneline -20'

# GitHub CLI
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