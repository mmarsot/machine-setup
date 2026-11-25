#!/usr/bin/env bash
# Install Nix (multi-user, flakes enabled) with the Determinate Systems installer.
# --no-init installs without an init system and starts nix-daemon in the
# background; it exists for containers and CI images that have no systemd.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=sudo/_common.sh
. "$here/_common.sh"
require_root

no_init=0
[ "${1:-}" = "--no-init" ] && no_init=1

if [ -x /nix/var/nix/profiles/default/bin/nix ]; then
  echo "Nix is already installed"
  exit 0
fi

installer="$(mktemp)"
trap 'rm -f "$installer"' EXIT
download https://install.determinate.systems/nix "$installer"

args=(install)
if [ "$no_init" = 1 ]; then
  args+=(linux --init none)
fi
args+=(--no-confirm)
sh "$installer" "${args[@]}"

if [ "$no_init" = 1 ]; then
  echo "Starting nix-daemon in the background (no init system)"
  nohup /nix/var/nix/profiles/default/bin/nix-daemon >/var/log/nix-daemon.log 2>&1 &
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -S /nix/var/nix/daemon-socket/socket ] && break
    sleep 1
  done
fi
echo "Nix installed"
