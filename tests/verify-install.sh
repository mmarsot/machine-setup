#!/usr/bin/env bash
# Assertions about a machine that setup.sh --unattended has just configured.
# Run inside the throwaway container by tests/docker.sh, as the setup user.
# The single quotes are deliberate: the inner login shell expands the variables.
# shellcheck disable=SC2016
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

echo "installed machine"
# This script itself runs in a plain (non-login) shell; the checks below use login shells.
PATH="$HOME/.nix-profile/bin:$HOME/.local/bin:$PATH"
login() { env -i HOME="$HOME" USER="$(id -un)" TERM=dumb bash -lc "$1" 2>/dev/null; }

for tool in node npm jq rg delta htop tmux uv python3 perl gh git \
  claude herdr treehouse no-mistakes gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi; do
  if login "command -v $tool" >/dev/null; then pass "$tool is on a login shell's PATH"; else fail "$tool is missing from a login shell's PATH"; fi
done
assert_eq "gh comes from Nix" "$(login 'command -v gh')" "$HOME/.nix-profile/bin/gh"
assert_eq "firstmate is a git clone" "$(test -d "$HOME/firstmate/.git" && echo yes || echo no)" "yes"
assert_eq "FM_HOME is set" "$(login 'echo $FM_HOME')" "$HOME/firstmate"
assert_eq "FM_BACKEND is herdr" "$(login 'echo $FM_BACKEND')" "herdr"
assert_eq "an interactive non-login shell sees FM_HOME" "$(env -i HOME="$HOME" USER="$(id -un)" PATH=/usr/bin:/bin bash -ic 'echo $FM_HOME' 2>/dev/null | tail -1)" "$HOME/firstmate"

# A pre-existing ~/.bashrc was kept, not clobbered.
assert_eq "the stock .bashrc was backed up" "$(test -e "$HOME/.bashrc.hm-backup" && echo yes || echo no)" "yes"

# Git and gh config.
helpers="$(login 'git config --get-all credential.https://github.com.helper')"
assert_contains "gh is the GitHub credential helper" "$helpers" "!gh auth git-credential"
assert_eq "credential.helper=store is not configured" "$(login 'git config --global --get-all credential.helper')" ""
assert_contains "gh config is ported" "$(cat "$HOME/.config/gh/config.yml")" "co: pr checkout"
assert_contains "git includes the personal identity file" "$(cat "$HOME/.config/git/config")" ".config/git/identity"

# Ported agent config, with the axi hooks merged in.
assert_eq "Claude model is ported" "$(jq -r .model "$HOME/.claude/settings.json")" "opus"
assert_eq "axi SessionStart hooks were registered" "$(jq -r '[.hooks.SessionStart[].hooks[].command] | sort | join(",")' "$HOME/.claude/settings.json")" "chrome-devtools-axi,gh-axi,lavish-axi"
assert_eq "Claude keybindings are ported" "$(jq -r '.bindings[0].bindings["meta+k"]' "$HOME/.claude/keybindings.json")" "voice:pushToTalk"
assert_contains "no-mistakes config is ported" "$(cat "$HOME/.no-mistakes/config.yaml")" 'ci_timeout: "168h"'
assert_contains "herdr config is ported" "$(cat "$HOME/.config/herdr/config.toml")" 'name = "catppuccin"'
assert_eq "npm globals install under ~/.local" "$(cat "$HOME/.npmrc")" "prefix=$HOME/.local"

# Nothing secret was created, and the env loader is inert without a vault file.
assert_eq "no env file without the vault step" "$(test -e "$HOME/.config/machine-setup/env" && echo yes || echo no)" "no"
assert_eq "no stored git credentials" "$(test -e "$HOME/.git-credentials" && echo yes || echo no)" "no"

finish
