#!/usr/bin/env bash
# Validate the command-line layer in a throwaway container: a fresh Ubuntu, an
# unprivileged user with passwordless sudo *inside the container*, setup.sh
# --unattended, then assertions, then a second run to prove it is idempotent.
# Nothing on the host is touched except the container.
#
#   tests/docker.sh [image]        default image: ubuntu:26.04
set -euo pipefail
IMAGE="${1:-ubuntu:26.04}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
NAME="machine-setup-test-$$"

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "==> container from $IMAGE"
docker run -d --name "$NAME" "$IMAGE" sleep infinity >/dev/null
docker exec "$NAME" bash -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq && apt-get install -y -qq sudo >/dev/null
  useradd -m -s /bin/bash tester
  echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester
  cat /etc/os-release | grep PRETTY_NAME'

echo "==> copy the repository (no .git: a fresh machine has no git until apt-prereqs runs)"
tar -C "$REPO_ROOT" --exclude=.git --exclude=.claude -cf - . \
  | docker exec -i -u tester "$NAME" bash -c 'mkdir -p ~/machine-setup && tar -C ~/machine-setup -xf -'

echo "==> setup.sh --unattended"
docker exec -u tester -e MS_NIX_INIT=none "$NAME" bash -c 'cd ~/machine-setup && ./setup.sh --unattended'

echo "==> verify"
docker exec -u tester "$NAME" bash -c 'cd ~/machine-setup && tests/verify-install.sh'

echo "==> second run must find everything already done"
out="$(docker exec -u tester -e MS_NIX_INIT=none "$NAME" bash -c 'cd ~/machine-setup && ./setup.sh --unattended')"
printf '%s\n' "$out" | tail -22
if printf '%s\n' "$out" | grep -E '^    (done|FAILED)'; then
  echo "second run was not a no-op" >&2
  exit 1
fi
echo "==> OK"
