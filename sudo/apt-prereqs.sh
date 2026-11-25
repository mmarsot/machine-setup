#!/usr/bin/env bash
# Install the apt packages everything else needs before Nix exists.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=sudo/_common.sh
. "$here/_common.sh"
require_root
require_ubuntu

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt_install curl git ca-certificates
echo "apt prerequisites installed: curl git ca-certificates"
