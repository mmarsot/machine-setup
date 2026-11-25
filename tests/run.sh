#!/usr/bin/env bash
# Run every test that needs no network and changes nothing outside a temp dir.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
rc=0
for t in "$here"/test-*.sh; do
  bash "$t" || rc=1
done
exit $rc
