#!/usr/bin/env bash
# scripts/vault-env.sh against a fake `bw`: structure checks, forbidden names, file mode.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
command -v jq >/dev/null || { echo "jq is required for this test"; exit 1; }

echo "vault-env"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

# A fake bw: `status` is unlocked; `get notes` prints $FAKE_NOTE; `sync` succeeds.
cat > "$work/bin/bw" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  status) echo '{"status":"unlocked"}' ;;
  sync) ;;
  get) printf '%s\n' "$*" > "${FAKE_LOG:-/dev/null}"; if [ -n "${FAKE_NOTE_MISSING:-}" ]; then exit 1; fi; printf '%s\n' "$FAKE_NOTE" ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$work/bin/bw"

fetch() { # fetch NOTE -> runs vault-env.sh, leaving output in $out and status in $rc
  out="$(PATH="$work/bin:$PATH" MS_ENV_FILE="$work/env" FAKE_NOTE="$1" "$REPO_ROOT/scripts/vault-env.sh" 2>&1)"
  rc=$?
}

rm -f "$work/env"
fetch $'# runtime tokens\nexport FOO_TOKEN=abc123\nBAR=baz qux'
assert_eq "a valid note is written" "$rc" "0"
assert_eq "env file has mode 600" "$(stat -c %a "$work/env" 2>/dev/null || stat -f %Lp "$work/env")" "600"
assert_contains "env file content is kept" "$(cat "$work/env")" "FOO_TOKEN=abc123"
assert_not_contains "secret values are never printed" "$out" "abc123"

rm -f "$work/env"
fetch $'GITHUB_RECOVERY=aaaa-bbbb'
assert_eq "recovery codes are refused" "$rc" "1"
assert_contains "refusal explains why" "$out" "never go in the environment"
assert_eq "nothing is written on refusal" "$(test -e "$work/env" && echo yes || echo no)" "no"
assert_not_contains "refused values are never printed" "$out" "aaaa-bbbb"

for key in BITWARDEN_DUAL_AUTH TOTP_SEED my_2fa_code MASTER_PASSWORD BACKUP_CODES; do
  rm -f "$work/env"; fetch "$key=x"
  assert_eq "$key is refused" "$rc" "1"
done

rm -f "$work/env"; fetch 'this is not an env file'
assert_eq "a note with no assignments is refused" "$rc" "1"
assert_not_contains "its text is never echoed" "$out" "this is not"

# The captain's format: pasted `export NAME=value` lines, quotes, CRLF, no trailing newline.
rm -f "$work/env"; fetch $'export A_TOKEN="q v"\r\nexport B_TOKEN=\'x y\'\r\nexport C=1'
assert_eq "export lines with quotes and CRLF work" "$rc" "0"
assert_eq "carriage returns are stripped" "$(grep -c $'\r' "$work/env")" "0"
assert_eq "the file sources cleanly" "$(bash -c ". '$work/env'; echo \$A_TOKEN/\$B_TOKEN/\$C")" "q v/x y/1"
assert_eq "env file keeps mode 600 here too" "$(stat -c %a "$work/env" 2>/dev/null || stat -f %Lp "$work/env")" "600"

rm -f "$work/env"; fetch ''
assert_eq "an empty note is refused" "$rc" "1"

rm -f "$work/env"
out="$(PATH="$work/bin:$PATH" MS_ENV_FILE="$work/env" FAKE_NOTE_MISSING=1 "$REPO_ROOT/scripts/vault-env.sh" 2>&1)"; rc=$?
assert_eq "a missing note fails" "$rc" "1"

# The default note is named "bashrc", and MS_VAULT_ITEM overrides it.
rm -f "$work/env"
PATH="$work/bin:$PATH" MS_ENV_FILE="$work/env" FAKE_NOTE="A=1" FAKE_LOG="$work/args" "$REPO_ROOT/scripts/vault-env.sh" >/dev/null 2>&1
assert_eq "default item is bashrc, read as notes" "$(cat "$work/args")" "get notes bashrc"
rm -f "$work/env"
PATH="$work/bin:$PATH" MS_ENV_FILE="$work/env" MS_VAULT_ITEM="other note" FAKE_NOTE="A=1" FAKE_LOG="$work/args" "$REPO_ROOT/scripts/vault-env.sh" >/dev/null 2>&1
assert_eq "MS_VAULT_ITEM overrides the item" "$(cat "$work/args")" "get notes other note"

# The loader accepts a 600 file and refuses a looser one.
printf 'LOADED_VAR=yes\n' > "$work/env"; chmod 600 "$work/env"
assert_eq "loader loads a mode-600 file (env var)" "$(MS_ENV_FILE="$work/env" bash -c ". '$REPO_ROOT/scripts/load-env.sh'; echo \${LOADED_VAR:-no}" 2>/dev/null)" "yes"
chmod 644 "$work/env"
assert_eq "loader refuses a world-readable file" "$(MS_ENV_FILE="$work/env" bash -c ". '$REPO_ROOT/scripts/load-env.sh'; echo \${LOADED_VAR:-no}" 2>/dev/null)" "no"

finish
