#!/usr/bin/env bash
# Install Google Chrome (stable) from Google's official .deb. The package's own
# postinst adds Google's apt repository, so apt keeps it updated afterwards.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=sudo/_common.sh
. "$here/_common.sh"
require_root
require_ubuntu
require_amd64

if dpkg -s google-chrome-stable >/dev/null 2>&1; then
  echo "Google Chrome is already installed"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
download https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb "$work/chrome.deb"
apt-get update
apt_install "$work/chrome.deb"
echo "Google Chrome installed"
