# Tiny assertion helpers for the test scripts. Sourced.
# shellcheck shell=bash
TESTS_FAILED=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

assert_contains() { # assert_contains NAME HAYSTACK NEEDLE
  if printf '%s' "$2" | grep -Fq -- "$3"; then pass "$1"; else fail "$1: expected to find: $3"; fi
}
assert_not_contains() {
  if printf '%s' "$2" | grep -Fq -- "$3"; then fail "$1: unexpected: $3"; else pass "$1"; fi
}
assert_eq() { # assert_eq NAME ACTUAL EXPECTED
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: got '$2', expected '$3'"; fi
}
finish() { if [ "$TESTS_FAILED" -ne 0 ]; then printf '%s test(s) failed\n' "$TESTS_FAILED"; exit 1; fi; }

# Run setup.sh with a throwaway HOME so nothing real is read or written.
setup_in_sandbox() {
  local sandbox
  sandbox="$(mktemp -d)"
  HOME="$sandbox" XDG_CONFIG_HOME="$sandbox/.config" XDG_STATE_HOME="$sandbox/.state" \
    MS_FORCE_DISPLAY=1 "$REPO_ROOT/setup.sh" "$@" 2>&1
  local rc=$?
  rm -rf "$sandbox"
  return $rc
}
