# Output, prompts and command wrappers for setup.sh. Sourced, never executed.
# Written for bash 3.2 (the macOS default): no associative arrays, no mapfile.
# shellcheck shell=bash

MS_YES=0         # --yes: answer yes to every question
MS_DRY=0         # --dry-run: print every change instead of making it
MS_UNATTENDED=0  # --unattended: --yes, and skip steps that need a person
export MS_FORCE=0  # --force: run steps even when they already look done

if [ -t 1 ]; then
  C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_GREEN=$'\033[32m'; C_OFF=$'\033[0m'
else
  C_BOLD=''; C_DIM=''; C_RED=''; C_YELLOW=''; C_GREEN=''; C_OFF=''
fi

say()  { printf '%s\n' "$*"; }
log()  { printf '%s==>%s %s%s%s\n' "$C_GREEN" "$C_OFF" "$C_BOLD" "$*" "$C_OFF"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%swarning:%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
err()  { printf '%serror:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ask "question" -> 0 for yes, 1 for no. Enter means yes.
ask() {
  local answer
  if [ "$MS_YES" = 1 ]; then
    printf '%s [Y/n] y\n' "$1"
    return 0
  fi
  printf '%s [Y/n] ' "$1"
  if ! IFS= read -r answer; then
    printf '\n'
    die "no answer available on stdin; run from a terminal, or pass --yes"
  fi
  case "$answer" in
    ''|[Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

# wait_enter "message": block until the owner presses Enter (continues when there is no terminal).
wait_enter() {
  local _
  printf '%s ' "$1"
  if [ ! -t 0 ]; then printf '(no terminal: continuing)\n'; return 0; fi
  IFS= read -r _ || true
}

# run CMD ARGS...: execute, or print under --dry-run.
run() {
  if [ "$MS_DRY" = 1 ]; then
    printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_OFF" "$*"
    return 0
  fi
  "$@"
}

# run_sh 'shell snippet': like run, for pipelines such as `curl ... | sh`.
run_sh() {
  if [ "$MS_DRY" = 1 ]; then
    printf '    %s[dry-run]%s %s\n' "$C_DIM" "$C_OFF" "$1"
    return 0
  fi
  bash -c "set -euo pipefail; $1"
}

# sudo_warmup: authenticate once, so the install steps can run without the owner
# standing by. This only caches the sudo password; it changes nothing.
sudo_warmup() {
  if [ "$MS_DRY" = 1 ] || [ "$MS_UNATTENDED" = 1 ]; then return 0; fi
  command -v sudo >/dev/null 2>&1 || die "sudo is not installed"
  info "Some steps run a script from sudo/ as root. Authenticate once now:"
  sudo -v
}

# run_sudo SCRIPT [ARGS...]: run a script from this repo's sudo/ directory as root.
run_sudo() {
  local script="$MS_REPO/sudo/$1"
  shift
  [ -f "$script" ] || die "missing $script"
  if [ "$MS_UNATTENDED" = 1 ]; then
    run sudo -n "$script" "$@" # never stop to ask for a password
  else
    run sudo "$script" "$@"
  fi
}
