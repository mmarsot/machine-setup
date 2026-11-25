#!/usr/bin/env bash
# machine-setup: take a fresh Ubuntu machine to the owner's development toolchain.
#
#   ./setup.sh                  ask yes/no for each step, then run the chosen ones
#   ./setup.sh --yes            answer yes to every step
#   ./setup.sh --unattended     --yes, and skip steps that need a person (CI)
#   ./setup.sh --dry-run        show every change without making any
#   ./setup.sh --only a,b       only these steps (see --list)
#   ./setup.sh --skip a,b       everything except these steps
#   ./setup.sh --force          run steps even when they already look done
#   ./setup.sh --list           list the steps and their dependencies
#
# It runs once on a fresh machine and never updates one. Every change that needs
# root is a script in sudo/, run only after a yes. See README.md and STRATEGY.md.
set -euo pipefail

MS_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export MS_REPO
MS_ONLY=""
MS_SKIP=""
MS_RUN_DIR=""
export USER="${USER:-$(id -un)}" # Home Manager's activate script requires it

# shellcheck source=lib/ui.sh
. "$MS_REPO/lib/ui.sh"
# shellcheck source=lib/steps.sh
. "$MS_REPO/lib/steps.sh"

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes) MS_YES=1 ;;
      --unattended) MS_YES=1; MS_UNATTENDED=1 ;;
      -n|--dry-run) MS_DRY=1; MS_YES=1 ;;
      --force) MS_FORCE=1 ;;
      --only) MS_ONLY="${2:?--only needs a comma-separated list}"; shift ;;
      --skip) MS_SKIP="${2:?--skip needs a comma-separated list}"; shift ;;
      --list) MS_LIST=1 ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; die "unknown option: $1" ;;
    esac
    shift
  done
  local id
  for id in $(printf '%s,%s' "$MS_ONLY" "$MS_SKIP" | tr ',' ' '); do
    valid_id "$id" || die "unknown step \"$id\" (see --list)"
  done
}

main() {
  MS_LIST=0
  parse_args "$@"
  if [ "$MS_LIST" = 1 ]; then list_steps; exit 0; fi

  case "$(uname -s)" in
    Linux) ;;
    Darwin) die "macOS is not a shipped target yet; the Nix base is ready for it, the Homebrew layer is not" ;;
    *) die "unsupported OS: $(uname -s)" ;;
  esac
  [ "$(id -u)" -ne 0 ] || [ "${MS_ALLOW_ROOT:-}" = 1 ] || die "run as your own user, not root (only the scripts in sudo/ get root)"

  MS_RUN_DIR="$(mktemp -d)"
  trap 'rm -rf "$MS_RUN_DIR"' EXIT
  export MS_RUN_DIR

  ms_refresh_path
  [ "$MS_DRY" = 1 ] && log "Dry run: nothing will be changed"
  plan
  if needs_sudo; then sudo_warmup; fi
  execute
  print_summary
  ! grep -qx failed "$MS_RUN_DIR"/* 2>/dev/null
}

main "$@"
