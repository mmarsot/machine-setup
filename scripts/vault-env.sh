#!/usr/bin/env bash
# Save your shell environment file from a pasted Bitwarden Secure Note.
#
# One Secure Note in your vault (default name: "bashrc") holds the runtime tokens
# as plain bash lines (export NAME=value) in its Notes field. Open it in the
# Bitwarden desktop app or browser extension, copy the Notes, and paste them here.
# The paste is read with the terminal echo off (nothing you paste is displayed),
# and ends on Ctrl-D. It is written to ~/.config/machine-setup/env with mode 600;
# ~/.bashrc (home/shell.nix, through scripts/load-env.sh) loads it in every shell.
# Only the variable NAMES are ever printed, never a value.
#
# Accepted lines: blank lines, `# comments`, and `export NAME=value`, where the
# value is one plain, 'single-quoted' or "double-quoted" word (no $ or backticks
# inside double quotes). Anything else is rejected, and the file is only written
# when every line is accepted. Two-factor recovery codes belong in the vault
# only, so a variable named like one is refused too.
#
#   MS_VAULT_ITEM   name of the secure note, shown in the instructions (default: bashrc)
#   MS_ENV_FILE     destination (default: ~/.config/machine-setup/env)
#
# Exit status: 0 saved, 10 skipped on request (nothing written), 1 failure.
set -euo pipefail

ITEM="${MS_VAULT_ITEM:-bashrc}"
DEST="${MS_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/machine-setup/env}"
EXIT_SKIPPED=10

# Names that must never reach the environment.
FORBIDDEN='RECOVERY|BACKUP_?CODES?|2FA|TWO_?FACTOR|TOTP|OTP_?SEED|DUAL_AUTH|MASTER_?PASSWORD'

fail() { printf 'vault-env: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

# A value is one word: plain, 'single-quoted' or "double-quoted". It cannot carry
# a command, because the file is sourced by every shell.
PLAIN='[A-Za-z0-9_@%+=:,./-]*'
SINGLE="'[^']*'"
DOUBLE='"[^"\\$`]*"'
LINE_RE="^[[:space:]]*export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=(${PLAIN}|${SINGLE}|${DOUBLE})[[:space:]]*$"
COMMENT_RE='^[[:space:]]*(#.*)?$'

# validate_env_file FILE: print one message per rejected line (the line number
# and the reason, never the line itself), then return 1. On success print the
# saved variable names, one per line, and return 0.
validate_env_file() {
  local file="$1" lineno=0 line key rejected=0 names=()
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    if [[ "$line" =~ $COMMENT_RE ]]; then
      continue
    elif [[ "$line" =~ $LINE_RE ]]; then
      key="${BASH_REMATCH[1]}"
      if printf '%s' "$key" | grep -Eiq "$FORBIDDEN"; then
        note "  line $lineno: $key is refused; recovery codes and master passwords never go in the environment, keep them in the vault only"
        rejected=1
      else
        names+=("$key")
      fi
    else
      note "  line $lineno: not a blank line, a # comment or an export NAME=value line (the value must be one plain, 'single-quoted' or \"double-quoted\" word)"
      rejected=1
    fi
  done < "$file"
  [ "$rejected" = 0 ] || return 1
  if [ "${#names[@]}" -eq 0 ]; then
    note "  nothing to save: expected lines like: export NAME=value"
    return 1
  fi
  printf '%s\n' "${names[@]}"
}

# confirm "question" DEFAULT(y|n): 0 for yes. End of input counts as the default.
confirm() {
  local answer hint='[y/N]'
  [ "$2" = y ] && hint='[Y/n]'
  printf '%s %s ' "$1" "$hint" >&2
  IFS= read -r answer || { printf '\n' >&2; answer=""; }
  case "$answer" in
    [Yy]*) return 0 ;;
    [Nn]*) return 1 ;;
    *) [ "$2" = y ] ;;
  esac
}

TMP=""         # the file being written, removed on any exit
SAVED_STTY=""  # terminal settings to restore after a hidden read

cleanup() {
  if [ -n "$SAVED_STTY" ]; then stty "$SAVED_STTY" 2>/dev/null || true; SAVED_STTY=""; fi
  if [ -n "$TMP" ]; then rm -f "$TMP"; fi
}

# read_paste FILE: read what is pasted until Ctrl-D (end of input) into FILE,
# without echoing it, with carriage returns stripped. The terminal state is
# restored even if the script is interrupted.
read_paste() {
  local out="$1"
  if [ -t 0 ]; then
    SAVED_STTY="$(stty -g)"
    stty -echo
  fi
  tr -d '\r' > "$out" || true
  if [ -n "$SAVED_STTY" ]; then
    stty "$SAVED_STTY" 2>/dev/null || true
    SAVED_STTY=""
    printf '\n' >&2
  fi
}

# bashrc_sources_loader: is the env file loaded by ~/.bashrc?
bashrc_sources_loader() {
  grep -qs 'machine-setup/load-env.sh' "$HOME/.bashrc" 2>/dev/null
}

main() {
  if [ -s "$DEST" ]; then
    note "$DEST already exists."
    confirm "Replace it with a new paste?" n || { note "Kept the existing file."; exit "$EXIT_SKIPPED"; }
  fi

  umask 077
  mkdir -p "$(dirname "$DEST")"
  local names
  TMP="$(mktemp "$DEST.XXXXXX")"
  trap cleanup EXIT
  trap 'exit 130' INT TERM

  note "In the Bitwarden desktop app or browser extension, open the Secure Note \"$ITEM\" and copy its Notes."
  note "Paste it here and press Enter, then Ctrl-D. Nothing you paste is displayed."
  while :; do
    read_paste "$TMP"
    if [ ! -s "$TMP" ]; then
      note "Nothing was pasted."
    elif names="$(validate_env_file "$TMP")"; then
      break
    else
      note "Nothing was saved. Fix the lines above in the note, or paste again."
    fi
    # Without a terminal (piped input) there is no one to retry.
    [ -t 0 ] || fail "no valid paste"
    confirm "Paste again? (n skips this step)" y || { note "Skipped; nothing was written."; exit "$EXIT_SKIPPED"; }
    : > "$TMP"
    note "Paste it here, then Ctrl-D."
  done

  # One trailing newline, so appending later never glues two lines together.
  [ -z "$(tail -c1 "$TMP")" ] || printf '\n' >> "$TMP"
  chmod 600 "$TMP"
  mv "$TMP" "$DEST"
  TMP=""

  echo "Saved $(printf '%s\n' "$names" | wc -l | tr -d ' ') variable(s) to $DEST (mode 600):"
  printf '  %s\n' $names
  if bashrc_sources_loader; then
    echo "New shells load it through ~/.bashrc."
  else
    note "warning: ~/.bashrc does not load it yet; run the home step of setup.sh (./setup.sh --only home --force)."
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
