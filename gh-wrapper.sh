#!/usr/bin/env bash
# Token-aware wrapper around the GitHub CLI.
#
# Installed at /usr/local/bin/gh (which shadows the real /usr/bin/gh on PATH), so it
# applies in EVERY shell context - interactive shells, `bash -c`, scripts, Makefiles
# and agent tool calls alike. A shell function only loads where ~/.aliases.sh is
# sourced (interactive shells), so the bare binary would otherwise run token-less in
# non-interactive contexts.
#
# Token selection mirrors the git credential helper in ~/.gitconfig: the read-write
# token inside the read-write project tree ($GH_RW_TREE), the read-only token (the
# safe default) everywhere else.
case "$PWD/" in
  "${GH_RW_TREE:-__no_rw_tree__}"/*) export GH_TOKEN="${GH_TOKEN_RW:-}" ;;
  *)                                 export GH_TOKEN="${GH_TOKEN_RO:-}" ;;
esac

exec /usr/bin/gh "$@"
