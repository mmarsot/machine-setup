#!/usr/bin/env bash
# Look for secrets that already leaked into the Nix store or into a world-readable
# file, on a machine that ran setup.sh. Read-only: it changes and deletes nothing.
#
# The Nix store is readable by every account on the machine, and a Home Manager
# dotfile such as ~/.bashrc is a symlink into it. Two things put a secret there:
#   - a secret in a file Nix copies in (the generated dotfile, or this repository), and
#   - editing the symlinked dotfile as root (for example `sudo nano ~/.bashrc`),
#     which writes through the link and changes the store file itself.
#
# It scans every file of every Home Manager generation, tells you which store paths
# Nix says were modified after they were built, and checks the mode of the env file.
# It prints file names, line counts and variable NAMES, never a value.
#
# Exit status: 0 nothing found, 1 something found (with the cleanup steps), 2 usage.
set -euo pipefail

MS_REPO="${MS_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
# shellcheck source=lib/secrets.sh
. "$MS_REPO/lib/secrets.sh"

[ "$#" -eq 0 ] || { echo "usage: scripts/audit-secrets.sh" >&2; exit 2; }

STORE="${MS_STORE_DIR:-/nix/store}" # overridable for tests
PROFILES="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles"
ENV_FILE="${MS_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/machine-setup/env}"
for d in /nix/var/nix/profiles/default/bin "$HOME/.nix-profile/bin"; do
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
found=0
need_repair=0
need_rotate=0

mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
# store_top PATH: the <store>/<hash>-<name> entry that holds PATH ("" outside the store).
store_top() {
  local rest
  case "$1" in
    "$STORE"/*) rest="${1#"$STORE"/}"; printf '%s/%s' "$STORE" "${rest%%/*}" ;;
  esac
}

# 1. The env file itself: mode 600, or other accounts can read the tokens.
if [ -e "$ENV_FILE" ] && [ ! -L "$ENV_FILE" ]; then
  mode="$(mode_of "$ENV_FILE")"
  case "$mode" in
    ?00) ;;
    *)
      found=1; need_rotate=1
      echo "$ENV_FILE has mode $mode: other accounts can read the tokens in it."
      echo "  Fix: chmod 600 \"$ENV_FILE\"   (then rotate its tokens if the machine has other accounts)"
      ;;
  esac
fi

# 2. Every file of every Home Manager generation. generations.txt: "<generation>\t<file>".
: > "$work/files.txt"
for gen in "$PROFILES"/home-manager-*-link; do
  [ -e "$gen/home-files" ] || continue
  num="${gen##*/home-manager-}"; num="${num%-link}"
  while IFS= read -r f; do
    printf '%s\t%s\n' "$num" "$(readlink -f "$f")" >> "$work/files.txt"
  done < <(find -L "$gen/home-files" -maxdepth 8 -type f 2>/dev/null)
done

cut -f2 "$work/files.txt" | sort -u > "$work/unique.txt"

# 2a. Store paths Nix itself says changed after they were built.
: > "$work/modified.txt"
if command -v nix-store >/dev/null 2>&1; then
  while IFS= read -r top; do
    [ -n "$top" ] || continue
    # Only Nix's own "was modified" verdict counts; an unreachable daemon is not one.
    case "$(nix-store --verify-path "$top" 2>&1 || true)" in
      *"was modified"*) printf '%s\n' "$top" >> "$work/modified.txt" ;;
    esac
  done < <(while IFS= read -r p; do store_top "$p"; echo; done < "$work/unique.txt" | sort -u)
fi

# 2b. Secrets in the content.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  top="$(store_top "$f")"
  count="$(ms_secret_count "$f")"
  modified=no
  if [ -n "$top" ] && grep -qxF "$top" "$work/modified.txt"; then modified=yes; fi
  [ "$count" -gt 0 ] || [ "$modified" = yes ] || continue
  gens="$(awk -F'\t' -v f="$f" '$2 == f { print $1 }' "$work/files.txt" | sort -n | paste -sd, -)"
  found=1
  echo "$f"
  echo "  in Home Manager generation(s): $gens"
  if [ "$modified" = yes ]; then
    need_repair=1
    echo "  Nix reports this store path was modified after it was built (editing a symlinked dotfile as root does this)."
  fi
  if [ "$count" -gt 0 ]; then
    need_rotate=1
    echo "  $count line(s) look like secrets; variable names: $(ms_secret_names "$f" | paste -sd' ' -)"
    echo "  Every account on this machine can read this file."
  fi
done < "$work/unique.txt"

[ "$found" = 1 ] || exit 0

echo
echo "Cleanup. Nothing below was done for you; nothing was deleted."
n=0
if [ "$need_rotate" = 1 ]; then
  n=$((n + 1)); echo "  $n. Treat each secret listed above as exposed: revoke it at its provider and issue a new one."
  echo "     Removing it from the file does not un-leak it. Editor backup files and swap files may hold copies too."
  n=$((n + 1)); echo "  $n. Keep the new values in ~/.config/machine-setup/env (scripts/vault-env.sh writes it with mode 600)."
  echo "     Never paste secrets into ~/.bashrc or any other Home Manager dotfile: they are read-only links into the Nix store."
fi
if [ "$need_repair" = 1 ]; then
  n=$((n + 1)); echo "  $n. Restore each modified store path to what Nix built (a rebuild alone does not: Nix trusts the path already there):"
  while IFS= read -r top; do
    [ -z "$top" ] || echo "       sudo nix-store --repair-path $top"
  done < "$work/modified.txt"
fi
n=$((n + 1)); echo "  $n. If a secret is in a generation that was built with it (not edited in later), rebuild first:"
echo "       $MS_REPO/setup.sh --force --only apt-prereqs,nix,home"
n=$((n + 1)); echo "  $n. Expire the old generations, then collect the store paths nothing refers to any more:"
echo "       nix-env --profile $PROFILES/home-manager --delete-generations old"
echo "       nix-collect-garbage"
n=$((n + 1)); echo "  $n. Run scripts/audit-secrets.sh again to confirm it finds nothing."
exit 1
