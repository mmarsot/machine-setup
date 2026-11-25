#!/usr/bin/env bash
# Seed a tool's config file from this repository without ever making it readable
# by other accounts. Called by the Home Manager activation in home/agents.nix.
#
#   seed-file.sh copy TARGET SOURCE        create TARGET from SOURCE unless it exists
#   seed-file.sh json TARGET SOURCE [JQ]   the same, and when TARGET exists merge
#                                          SOURCE underneath it (existing values win)
#
# These files belong to tools that later store credentials in them (an npm auth
# token in ~/.npmrc, an env block in Claude Code's settings.json), so a new file is
# created with mode 600 and an existing file keeps the mode it has: the merge
# rewrites it in place instead of replacing it with a freshly created one.
set -euo pipefail
umask 077

mode="${1:?mode}" target="${2:?target}" source="${3:?source}" jq="${4:-jq}"

if [ ! -e "$target" ]; then
  mkdir -p "$(dirname "$target")"
  install -m 600 "$source" "$target"
  exit 0
fi
[ "$mode" = json ] || exit 0

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
if "$jq" -s '.[0] * .[1]' "$source" "$target" > "$tmp" 2>/dev/null; then
  cat "$tmp" > "$target"
else
  echo "machine-setup: $target is not valid JSON; leaving it untouched" >&2
fi
