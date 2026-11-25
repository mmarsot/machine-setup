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

# Answering "n" declines a step and skips what needs it, so nothing runs.
sandbox="$(mktemp -d)"
out="$(printf 'n\n' | HOME="$sandbox" XDG_CONFIG_HOME="$sandbox/.config" XDG_STATE_HOME="$sandbox/.state" \
  "$REPO_ROOT/setup.sh" --only apt-prereqs,nix,home --force 2>&1)"
rm -rf "$sandbox"
assert_contains "answering n declines the step" "$out" "skipped   apt-prereqs (declined)"
assert_contains "a declined step skips its dependents" "$out" "skipped   nix (needs apt-prereqs)"
assert_contains "the skip follows the dependency chain" "$out" "skipped   home (needs nix)"

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

# Every sudo script is run by a step, and every root command is a repo sudo/ script.
out="$(setup_in_sandbox --dry-run --force)"
for f in "$REPO_ROOT"/sudo/*.sh; do
  b="$(basename "$f")"; [ "$b" = _common.sh ] && continue
  assert_contains "sudo/$b is run by a step" "$out" "[dry-run] sudo $REPO_ROOT/sudo/$b"
done
stray="$(printf '%s\n' "$out" | grep -F '[dry-run]' | grep -wF sudo | grep -vF "[dry-run] sudo $REPO_ROOT/sudo/")"
assert_eq "no root command outside the sudo/ scripts" "$stray" ""

finish
