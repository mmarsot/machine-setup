# Presence-only secret detection, shared by setup.sh (before Nix copies the
# repository into the world-readable store) and scripts/audit-secrets.sh. Sourced,
# never executed.
#
# Nothing here ever prints a secret value: the functions return file names, line
# counts and variable NAMES only, and every grep is -l, -c or a name-only sed.
# shellcheck shell=bash

# Token shapes: Anthropic, GitHub, AWS (including Bedrock API keys), Hugging Face,
# Google, Slack, npm, GitLab, private keys.
MS_SECRET_SHAPES='sk-ant-[A-Za-z0-9_-]{10,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gho_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|ABSK[A-Za-z0-9+/=]{20,}|hf_[A-Za-z0-9]{30,}|AIza[0-9A-Za-z_-]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|npm_[A-Za-z0-9]{30,}|glpat-[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'

# A literal assignment to a secret-looking name: NAME=value (optionally exported)
# whose value is eight or more characters and not a variable reference.
MS_SECRET_ASSIGN='^[[:space:]]*(export[[:space:]]+)?[A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|ACCESS_?KEY|RECOVERY|BACKUP_?CODES?|2FA|TWO_?FACTOR|DUAL_AUTH|CREDENTIAL|BEARER|PRIVATE_?KEY)[A-Za-z0-9_]*=["'"'"']?[^$"'"'"'[:space:]][^[:space:]]{7,}'

# ms_secret_count FILE: how many lines look like a secret (0 for an unreadable file).
ms_secret_count() {
  local n
  n="$(grep -IcsE -e "$MS_SECRET_SHAPES" -e "$MS_SECRET_ASSIGN" "$1" 2>/dev/null)" || true
  printf '%s\n' "${n:-0}"
}

# ms_secret_names FILE: the variable NAMES of the literal secret assignments, one
# per line. sed prints only on a successful match, so a value can never be shown.
ms_secret_names() {
  grep -IsE "$MS_SECRET_ASSIGN" "$1" 2>/dev/null \
    | sed -nE 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z0-9_]+)=.*/\2/p' \
    | sort -u
}

# ms_files_with_secrets FILE...: print the names of the files that contain a secret.
ms_files_with_secrets() {
  [ "$#" -gt 0 ] || return 0
  grep -IlsE -e "$MS_SECRET_SHAPES" -e "$MS_SECRET_ASSIGN" -- "$@" 2>/dev/null || true
}

# ms_store_bound_files DIR: the files `nix build DIR#...` copies into the Nix store,
# one per line, relative to DIR. Nix copies a git checkout's tracked files (with
# their uncommitted edits) and every file of a directory that is not a git checkout.
ms_store_bound_files() {
  if git -C "$1" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$1" ls-files --cached
  else
    (cd "$1" && find . -type f -not -path './.git/*' | sed 's|^\./||')
  fi
}

# ms_scan_store_bound DIR: print the files Nix would copy into the store that look
# like they hold a secret. Returns 1 when there is at least one.
ms_scan_store_bound() {
  local dir="$1" f hits
  local paths=()
  while IFS= read -r f; do
    [ -f "$dir/$f" ] && paths+=("$dir/$f")
  done < <(ms_store_bound_files "$dir")
  [ "${#paths[@]}" -gt 0 ] || return 0
  hits="$(ms_files_with_secrets "${paths[@]}")"
  [ -z "$hits" ] || { printf '%s\n' "$hits" | sed "s|^$dir/||"; return 1; }
}
