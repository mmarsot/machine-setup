#!/usr/bin/env bash
# Fetch the shell environment file from the Bitwarden vault.
#
# One Secure Note item in the vault (default name: "bashrc") holds the
# runtime tokens as plain bash lines (export NAME=value) in its Notes field. No file attachment is
# used, so this works on Bitwarden's free plan. This script writes it to
# ~/.config/machine-setup/env with mode 600; ~/.bashrc (home/shell.nix) loads it.
# Nothing is ever printed, logged or committed. Two-factor recovery codes belong
# in the vault only, so a note that defines such a variable is refused.
#
#   MS_VAULT_ITEM   name of the secure note (default: bashrc)
#   MS_ENV_FILE     destination (default: ~/.config/machine-setup/env)
set -euo pipefail

ITEM="${MS_VAULT_ITEM:-bashrc}"
DEST="${MS_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/machine-setup/env}"

# Names that must never reach the environment.
FORBIDDEN='RECOVERY|BACKUP_?CODES?|2FA|TWO_?FACTOR|TOTP|OTP_?SEED|DUAL_AUTH|MASTER_?PASSWORD'

fail() { printf 'vault-env: %s\n' "$*" >&2; exit 1; }

# validate_env_file FILE: the note is plain bash lines such as `export NAME=value`
# (quotes allowed), written as-is. Only two things are checked, and values are
# never printed: it assigns at least one variable, and none of the names is one
# that must stay out of the environment.
validate_env_file() {
  local file="$1" lineno=0 line key entries=0
  [ -s "$file" ] || fail "the vault note is empty"
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)= ]]; then
      key="${BASH_REMATCH[2]}"
      entries=$((entries + 1))
      if printf '%s' "$key" | grep -Eiq "$FORBIDDEN"; then
        fail "line $lineno defines $key: recovery codes and master passwords never go in the environment; keep them in the vault only"
      fi
    fi
  done < "$file"
  [ "$entries" -gt 0 ] || fail "the vault note assigns no variables (expected lines like: export NAME=value)"
}

main() {
  command -v bw >/dev/null 2>&1 || fail "the Bitwarden CLI (bw) is not installed; run the home step first"
  command -v jq >/dev/null 2>&1 || fail "jq is not installed; run the home step first"

  local status
  status="$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || true)"
  case "$status" in
    unlocked) ;;
    locked)
      echo "Unlock the vault (master password):" >&2
      BW_SESSION="$(bw unlock --raw)"; export BW_SESSION ;;
    *)
      echo "Log in to Bitwarden (email, master password, two-step code):" >&2
      BW_SESSION="$(bw login --raw)"; export BW_SESSION ;;
  esac
  bw sync >/dev/null

  umask 077
  mkdir -p "$(dirname "$DEST")"
  local tmp
  tmp="$(mktemp "$DEST.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  if ! bw get notes "$ITEM" 2>/dev/null | tr -d '\r' > "$tmp" || [ ! -s "$tmp" ]; then
    fail "no Secure Note named \"$ITEM\" with notes in the vault. Create one (export NAME=value lines) and re-run, or skip this step"
  fi
  validate_env_file "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$DEST"
  trap - EXIT
  echo "Wrote $DEST (mode 600). New shells load it."
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
