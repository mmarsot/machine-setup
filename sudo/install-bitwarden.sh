#!/usr/bin/env bash
# Install the Bitwarden desktop app from Bitwarden's official .deb.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=sudo/_common.sh
. "$here/_common.sh"
require_root
require_ubuntu
require_amd64

if dpkg -s bitwarden >/dev/null 2>&1; then
  echo "Bitwarden desktop is already installed"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
download "https://vault.bitwarden.com/download/?app=desktop&platform=linux&variant=deb" "$work/bitwarden.deb"
if ! dpkg-deb -f "$work/bitwarden.deb" Package >/dev/null 2>&1; then
  echo "download is not a .deb package" >&2
  exit 1
fi
apt-get update
apt_install "$work/bitwarden.deb"
echo "Bitwarden desktop installed"
