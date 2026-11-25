# Load the vault-fetched env file into the current shell. Sourced from ~/.bashrc
# (via home/shell.nix) and by setup.sh before it launches Claude Code. Refuses a
# file that is not owned by the current user with mode 600.
# shellcheck shell=bash
__ms_env="${MS_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/machine-setup/env}"
if [ -f "$__ms_env" ]; then
  # ls shows the mode as -rw-------: the owner's bits, then six dashes for group and other.
  __ms_mode="$(ls -ld "$__ms_env")"
  case "$__ms_mode" in
    -???------*)
      if [ -O "$__ms_env" ]; then
        set -a
        # shellcheck disable=SC1090
        . "$__ms_env"
        set +a
      else
        echo "machine-setup: ignoring $__ms_env (not owned by you)" >&2
      fi
      ;;
    *) echo "machine-setup: ignoring $__ms_env (must have mode 600)" >&2 ;;
  esac
  unset __ms_mode
fi
unset __ms_env
