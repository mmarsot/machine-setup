# Shared helpers for the sudo scripts. Sourced, never executed.
# shellcheck shell=bash

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "$0 must run as root: sudo $0" >&2
    exit 1
  fi
}

require_ubuntu() {
  if [ ! -r /etc/os-release ] || ! grep -qiE '^ID(_LIKE)?=.*(ubuntu|debian)' /etc/os-release; then
    echo "$0: this script supports Ubuntu (apt) only" >&2
    exit 1
  fi
}

# download <url> <dest>
download() {
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "$2" "$1"
}

apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y --no-install-recommends "$@"
}

# amd64 only: Google ships no arm64 Linux Chrome and Bitwarden's .deb link is x64.
require_amd64() {
  local arch
  arch="$(dpkg --print-architecture)"
  if [ "$arch" != "amd64" ]; then
    echo "$0: only amd64 is supported (this machine is $arch)" >&2
    exit 1
  fi
}
