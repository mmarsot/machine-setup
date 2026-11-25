#!/usr/bin/env bash
# Plan/run engine: dry run, dependencies, skipping, unattended mode. Changes nothing.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

echo "engine"

out="$(setup_in_sandbox --dry-run --force)"
for id in $("$REPO_ROOT/setup.sh" --list | cut -d' ' -f1); do
  assert_contains "dry run plans $id" "$out" "would run $id"
done
assert_contains "sudo steps go through repo scripts" "$out" "sudo/install-chrome.sh"
assert_not_contains "dry run changes nothing" "$out" "FAILED"

out="$(setup_in_sandbox --dry-run --force --skip nix)"
assert_contains "declining nix skips home" "$out" "skipped   home (needs nix)"
assert_contains "declining nix skips axi-tools through home" "$out" "skipped   axi-tools (needs home)"
assert_contains "declining nix skips firstmate" "$out" "skipped   firstmate (needs home)"
assert_contains "independent steps still run" "$out" "would run chrome"

out="$(setup_in_sandbox --dry-run --force --skip chrome-signin)"
assert_contains "no Chrome sign-in means no Bitwarden extension" "$out" "skipped   bitwarden-extension (needs chrome-signin)"
assert_contains "Bitwarden itself is unaffected" "$out" "would run bitwarden-signin"

out="$(setup_in_sandbox --dry-run --force --skip chrome)"
assert_contains "no Chrome skips its sign-in" "$out" "skipped   chrome-signin (needs chrome)"

out="$(setup_in_sandbox --dry-run --force --only apt-prereqs,chrome)"
assert_contains "--only runs just the selected steps" "$out" "would run chrome"
assert_not_contains "--only leaves the rest" "$out" "would run herdr"

out="$(setup_in_sandbox --unattended --dry-run --force)"
assert_contains "unattended skips steps that need a person" "$out" "needs a person (--unattended)"
assert_contains "unattended never launches Claude" "$out" "skipped   launch (needs a person (--unattended))"
assert_contains "unattended still installs tools" "$out" "would run claude-code"

out="$(setup_in_sandbox --dry-run --force --skip bogus)"
assert_contains "unknown step is rejected" "$out" "unknown step"

# Answering "n" declines a step and skips what needs it.
sandbox="$(mktemp -d)"
out="$(printf 'y\ny\nn\n' | HOME="$sandbox" XDG_CONFIG_HOME="$sandbox/.config" XDG_STATE_HOME="$sandbox/.state" \
  "$REPO_ROOT/setup.sh" --only apt-prereqs,nix,home --force 2>&1 | sed -n '1,20p')"
rm -rf "$sandbox"
assert_contains "interactive answers are honored" "$out" "[Y/n]"

# Every step's dependencies come earlier in the order.
(
  # shellcheck disable=SC1091
  . "$REPO_ROOT/lib/ui.sh"; . "$REPO_ROOT/lib/steps.sh"
  seen=" "; bad=""
  for id in $MS_STEPS; do
    for d in $(hook deps "$id"); do case "$seen" in *" $d "*) ;; *) bad="$bad $id->$d" ;; esac; done
    seen="$seen$id "
  done
  [ -z "$bad" ] || { echo "dependencies listed after their dependents:$bad"; exit 1; }
)
assert_eq "dependencies precede dependents" "$?" "0"

# Every sudo script is used by a step, and sudo appears nowhere else.
for f in "$REPO_ROOT"/sudo/*.sh; do
  b="$(basename "$f")"; [ "$b" = _common.sh ] && continue
  if grep -q "run_sudo $b\|sudo_[a-z_]*() *{ echo $b" "$REPO_ROOT/lib/steps.sh"; then pass "sudo/$b is wired to a step"; else fail "sudo/$b is not used by any step"; fi
done
stray="$(grep -rnE '(^|[;&|(]|run |exec |command )[[:space:]]*sudo[[:space:]]' "$REPO_ROOT" --include='*.sh' --include='*.nix' --exclude-dir=.git --exclude-dir=tests | grep -v '^[^:]*:[0-9]*: *#' | grep -v 'lib/ui.sh')"
assert_eq "no sudo calls outside lib/ui.sh run_sudo" "$stray" ""

finish
