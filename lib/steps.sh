# Step definitions and the plan/run engine. Sourced by setup.sh, never executed.
#
# A step <id> (hyphens become underscores in function names) provides:
#   desc_<id>   the yes/no question, without the trailing "?"
#   deps_<id>   space-separated ids of the steps it needs (all listed earlier)
#   flags_<id>  words: interactive (needs a person: skipped by --unattended),
#               display (needs a graphical session), always (never marked done)
#   sudo_<id>   (optional) the sudo/ script the step runs as root
#   check_<id>  return 0 when the step is already satisfied on this machine
#   run_<id>    do the work; every change goes through run / run_sh / run_sudo
# shellcheck shell=bash

# Order matters: everything that installs without a person comes first, so the
# owner answers every question once, walks away, and returns for the logins.
# The root steps come first, together, while the sudo password is still cached.
MS_STEPS="apt-prereqs chrome bitwarden nix home claude-code axi-tools herdr treehouse no-mistakes firstmate git-identity chrome-signin bitwarden-signin bitwarden-extension vault-env github-auth launch"

FM_HOME="${FM_HOME:-$HOME/firstmate}"
MS_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/machine-setup"
MS_ENV_DEFAULT="${XDG_CONFIG_HOME:-$HOME/.config}/machine-setup/env"

fn_id() { printf '%s' "${1//-/_}"; }
hook() { local h; h="$1_$(fn_id "$2")"; shift 2; "$h" "$@"; }
has_hook() { [ "$(type -t "$1_$(fn_id "$2")")" = function ]; }

ms_refresh_path() {
  local d
  if [ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    set +u
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    set -u
  fi
  for d in /nix/var/nix/profiles/default/bin "$HOME/.nix-profile/bin" "$HOME/.local/bin"; do
    case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
  done
  export PATH
}

has_display() { [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; }
have() { command -v "$1" >/dev/null 2>&1; }
detach() { # detach CMD ARGS...: start a GUI program that outlives setup.sh
  if [ "$MS_DRY" = 1 ]; then run "$@"; return 0; fi
  nohup "$@" >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# ---------------------------------------------------------------- apt-prereqs
desc_apt_prereqs()  { echo "Install curl, git and ca-certificates with apt"; }
deps_apt_prereqs()  { :; }
flags_apt_prereqs() { :; }
sudo_apt_prereqs()  { echo apt-prereqs.sh; }
check_apt_prereqs() { have curl && have git && [ -r /etc/ssl/certs/ca-certificates.crt ]; }
run_apt_prereqs()   { run_sudo apt-prereqs.sh; }

# ------------------------------------------------------------------------ nix
desc_nix()  { echo "Install Nix (the shared package manager for Ubuntu and macOS)"; }
deps_nix()  { echo apt-prereqs; }
flags_nix() { :; }
sudo_nix()  { echo install-nix.sh; }
check_nix() { have nix || [ -x /nix/var/nix/profiles/default/bin/nix ]; }
# MS_NIX_INIT=none is for containers and CI images without systemd.
run_nix()   { if [ "${MS_NIX_INIT:-}" = none ]; then run_sudo install-nix.sh --no-init; else run_sudo install-nix.sh; fi; }

# ----------------------------------------------------------------------- home
desc_home()  { echo "Apply the Home Manager base: command-line tools, shell, git and gh config, ported agent config"; }
deps_home()  { echo nix; }
flags_home() { :; }
check_home() { return 1; } # tracked by its done marker only
run_home() {
  ms_refresh_path
  local flake="$MS_REPO#homeConfigurations.default.activationPackage"
  if [ "$MS_DRY" = 1 ]; then
    info "[dry-run] nix build --impure --no-write-lock-file $flake"
    info "[dry-run] HOME_MANAGER_BACKUP_EXT=hm-backup <result>/activate   (existing dotfiles are kept as *.hm-backup)"
    return 0
  fi
  local out
  out="$(USER="${USER:-$(id -un)}" nix --extra-experimental-features 'nix-command flakes' \
    build --impure --no-write-lock-file --no-link --print-out-paths "$flake")"
  HOME_MANAGER_BACKUP_EXT=hm-backup "$out/activate"
  ms_refresh_path
}

# --------------------------------------------------------------------- chrome
desc_chrome()  { echo "Install Google Chrome"; }
deps_chrome()  { echo apt-prereqs; }
flags_chrome() { :; }
sudo_chrome()  { echo install-chrome.sh; }
check_chrome() { have google-chrome-stable || dpkg -s google-chrome-stable >/dev/null 2>&1; }
run_chrome()   { run_sudo install-chrome.sh; }

# ------------------------------------------------------------------ bitwarden
desc_bitwarden()  { echo "Install the Bitwarden desktop app"; }
deps_bitwarden()  { echo apt-prereqs; }
flags_bitwarden() { :; }
sudo_bitwarden()  { echo install-bitwarden.sh; }
check_bitwarden() { dpkg -s bitwarden >/dev/null 2>&1 || [ -x /opt/Bitwarden/bitwarden-app ]; }
run_bitwarden()   { run_sudo install-bitwarden.sh; }

# ---------------------------------------------------------------- claude-code
desc_claude_code()  { echo "Install Claude Code with its own installer"; }
deps_claude_code()  { echo apt-prereqs; }
flags_claude_code() { :; }
check_claude_code() { have claude; }
run_claude_code()   { ms_refresh_path; run_sh 'curl -fsSL https://claude.ai/install.sh | bash'; }

# ------------------------------------------------------------------ axi-tools
AXI_PACKAGES="gh-axi chrome-devtools-axi lavish-axi tasks-axi quota-axi"
desc_axi_tools()  { echo "Install the axi tools ($AXI_PACKAGES) with npm and register their hooks"; }
deps_axi_tools()  { echo home claude-code; }
flags_axi_tools() { :; }
check_axi_tools() { local t; for t in $AXI_PACKAGES; do have "$t" || return 1; done; }
run_axi_tools() {
  ms_refresh_path
  export NPM_CONFIG_PREFIX="$HOME/.local"
  # shellcheck disable=SC2086 # word splitting of the package list is intended
  run npm install -g $AXI_PACKAGES
  # After Claude Code exists, so each hook lands in its settings.json.
  run gh-axi setup hooks
  run chrome-devtools-axi setup hooks
  run lavish-axi setup hooks
}

# ---------------------------------------------------------------------- herdr
desc_herdr()  { echo "Install herdr with its own installer"; }
deps_herdr()  { echo apt-prereqs; }
flags_herdr() { :; }
check_herdr() { have herdr; }
run_herdr()   { ms_refresh_path; run_sh 'curl -fsSL https://herdr.dev/install.sh | sh'; }

# ------------------------------------------------------------------ treehouse
desc_treehouse()  { echo "Install treehouse with its own installer"; }
deps_treehouse()  { echo apt-prereqs; }
flags_treehouse() { :; }
check_treehouse() { have treehouse; }
run_treehouse()   { ms_refresh_path; run_sh 'curl -fsSL https://kunchenguid.github.io/treehouse/install.sh | sh'; }

# ---------------------------------------------------------------- no-mistakes
desc_no_mistakes()  { echo "Install no-mistakes with its own installer and start its daemon service"; }
deps_no_mistakes()  { echo apt-prereqs claude-code; }
flags_no_mistakes() { :; }
check_no_mistakes() { have no-mistakes; }
run_no_mistakes() {
  ms_refresh_path
  # The global config (~/.no-mistakes/config.yaml) was seeded by the home step.
  run_sh 'curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh'
  if [ "$MS_DRY" != 1 ] && ! { have systemctl && systemctl --user show-environment >/dev/null 2>&1; }; then
    warn "no systemd user session here; start the daemon later from a desktop session with: no-mistakes daemon start"
    return 0
  fi
  # no-mistakes writes its own unit (the file name carries a per-install hash).
  run no-mistakes daemon start
  no_mistakes_path_dropin
}
# The generated unit's PATH has no Nix profile, so the daemon would not find the
# Nix-provided gh and git. A drop-in adds it without touching the generated file.
no_mistakes_path_dropin() {
  local path="$HOME/.local/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  if [ "$MS_DRY" = 1 ]; then
    info "[dry-run] add a systemd drop-in to no-mistakes-daemon-*.service putting ~/.nix-profile/bin on its PATH, then restart it"
    return 0
  fi
  local unit name
  for unit in "$HOME"/.config/systemd/user/no-mistakes-daemon-*.service; do
    [ -e "$unit" ] || continue
    name="$(basename "$unit")"
    mkdir -p "$unit.d"
    printf '[Service]\nEnvironment="PATH=%s"\n' "$path" > "$unit.d/10-machine-setup-path.conf"
    systemctl --user daemon-reload
    systemctl --user restart "$name"
  done
}

# ------------------------------------------------------------------ firstmate
desc_firstmate()  { echo "Clone firstmate into $FM_HOME"; }
deps_firstmate()  { echo home claude-code axi-tools treehouse no-mistakes; }
flags_firstmate() { :; }
check_firstmate() { [ -d "$FM_HOME/.git" ]; }
run_firstmate()   { ms_refresh_path; run git clone https://github.com/kunchenguid/firstmate "$FM_HOME"; }

# ---------------------------------------------------------------- git-identity
GIT_IDENTITY_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/git/identity"
desc_git_identity()  { echo "Set your git name and email (kept out of this repository)"; }
deps_git_identity()  { echo home; }
flags_git_identity() { echo interactive; }
check_git_identity() { [ -n "$(git config --file "$GIT_IDENTITY_FILE" user.email 2>/dev/null)" ]; }
run_git_identity() {
  ms_refresh_path
  local name="${MS_GIT_NAME:-}" email="${MS_GIT_EMAIL:-}"
  if [ "$MS_DRY" = 1 ]; then
    info "[dry-run] ask for a name and email, then git config --file $GIT_IDENTITY_FILE"
    return 0
  fi
  if [ -z "$name" ]; then printf '    Git name: '; IFS= read -r name; fi
  if [ -z "$email" ]; then printf '    Git email: '; IFS= read -r email; fi
  [ -n "$name" ] && [ -n "$email" ] || die "name and email are both required (skip this step instead)"
  mkdir -p "$(dirname "$GIT_IDENTITY_FILE")"
  git config --file "$GIT_IDENTITY_FILE" user.name "$name"
  git config --file "$GIT_IDENTITY_FILE" user.email "$email"
}

# ---------------------------------------------------------------- chrome-signin
CHROME_PREFS="$HOME/.config/google-chrome/Default/Preferences"
desc_chrome_signin()  { echo "Open Chrome so you can sign in to it"; }
deps_chrome_signin()  { echo chrome; }
flags_chrome_signin() { echo "interactive display"; }
check_chrome_signin() {
  have jq && [ -r "$CHROME_PREFS" ] && jq -e '(.account_info // []) | length > 0' "$CHROME_PREFS" >/dev/null 2>&1
}
run_chrome_signin() {
  ms_refresh_path
  detach google-chrome-stable --no-first-run https://accounts.google.com/
  wait_enter "    Sign in to Chrome from its profile menu (top right), then press Enter."
}

# ------------------------------------------------------------ bitwarden-signin
BW_AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/bitwarden.desktop"
desc_bitwarden_signin()  { echo "Open the Bitwarden desktop app so you can log in and enable biometric unlock"; }
deps_bitwarden_signin()  { echo bitwarden; }
flags_bitwarden_signin() { echo "interactive display"; }
check_bitwarden_signin() { return 1; }
run_bitwarden_signin() {
  # The desktop app must be running for the browser extension to unlock with biometrics.
  if [ "$MS_DRY" = 1 ]; then
    info "[dry-run] write $BW_AUTOSTART (start Bitwarden at login)"
  else
    mkdir -p "$(dirname "$BW_AUTOSTART")"
    printf '[Desktop Entry]\nType=Application\nName=Bitwarden\nExec=/opt/Bitwarden/bitwarden-app --autostart\nX-GNOME-Autostart-enabled=true\n' > "$BW_AUTOSTART"
  fi
  detach /opt/Bitwarden/bitwarden-app
  info "In the Bitwarden app: log in (email, master password, two-step code), then in Settings"
  info "turn on \"Unlock with biometrics\" and \"Allow browser integration\"."
  wait_enter "    Press Enter when Bitwarden is logged in."
}

# ---------------------------------------------------------- bitwarden-extension
desc_bitwarden_extension()  { echo "Open the Chrome Web Store so you can add the Bitwarden extension"; }
deps_bitwarden_extension()  { echo chrome-signin bitwarden-signin; }
flags_bitwarden_extension() { echo "interactive display"; }
check_bitwarden_extension() { return 1; }
run_bitwarden_extension() {
  ms_refresh_path
  detach google-chrome-stable https://chromewebstore.google.com/detail/bitwarden-password-manager/nngceckbapebfimnlniiiahkandclblb
  info "Click \"Add to Chrome\", then in the extension's settings choose \"Unlock with biometrics\"."
  wait_enter "    Press Enter when the extension is installed."
}

# ------------------------------------------------------------------- vault-env
desc_vault_env()  { echo "Fetch your shell environment file from the Bitwarden vault (Secure Note \"${MS_VAULT_ITEM:-bashrc}\")"; }
deps_vault_env()  { echo home; }
flags_vault_env() { echo interactive; }
check_vault_env() { [ -s "${MS_ENV_FILE:-$MS_ENV_DEFAULT}" ]; }
run_vault_env()   { ms_refresh_path; run "$MS_REPO/scripts/vault-env.sh"; }

# ----------------------------------------------------------------- github-auth
desc_github_auth()  { echo "Log in to GitHub with gh"; }
deps_github_auth()  { echo home; }
flags_github_auth() { echo interactive; }
check_github_auth() { have gh && gh auth status >/dev/null 2>&1; }
run_github_auth()   {
  ms_refresh_path
  # Git's credential helper is already configured by the home step (no setup-git needed).
  run gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key
}

# --------------------------------------------------------------------- launch
desc_launch()  { echo "Start Claude Code in firstmate to configure this machine with you"; }
deps_launch()  { echo firstmate claude-code; }
flags_launch() { echo "interactive always"; }
check_launch() { return 1; }
run_launch() {
  ms_refresh_path
  local prompt
  prompt="$(cat "$MS_REPO/prompts/configure-machine.md")"
  prompt="$prompt

The machine-setup repository is at $MS_REPO; its sudo scripts are in $MS_REPO/sudo."
  if [ "$MS_DRY" = 1 ]; then
    info "[dry-run] cd $FM_HOME && load ~/.config/machine-setup/env && claude \"<prompt from prompts/configure-machine.md>\""
    return 0
  fi
  [ -d "$FM_HOME" ] || die "firstmate is not cloned at $FM_HOME"
  print_summary
  cd "$FM_HOME"
  export FM_HOME FM_BACKEND="${FM_BACKEND:-herdr}" MS_REPO
  # shellcheck disable=SC1091
  . "$MS_REPO/scripts/load-env.sh"
  # A Claude Code token in the vault env means Claude is already signed in, so
  # there is no login to walk through; still make sure it starts.
  if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    info "Claude Code signs in with CLAUDE_CODE_OAUTH_TOKEN from the vault env file."
  fi
  claude --version >/dev/null || die "claude does not start"
  exec claude "$prompt"
}

# ------------------------------------------------------------------------ engine
set_status() { printf '%s' "$2" > "$MS_RUN_DIR/$1"; }
get_status() { if [ -f "$MS_RUN_DIR/$1" ]; then cat "$MS_RUN_DIR/$1"; else printf none; fi; }
marker() { printf '%s/done/%s' "$MS_STATE_DIR" "$1"; }

csv_has() { case ",$1," in *",$2,"*) return 0 ;; *) return 1 ;; esac; }
valid_id() { case " $MS_STEPS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

dep_ok() { # dep_ok ID PHASE
  case "$(get_status "$1")" in
    already|done|dry) return 0 ;;
    planned) [ "$2" = plan ] ;;
    *) return 1 ;;
  esac
}

unmet_dep() { # prints the first dependency that is not satisfied
  local d
  for d in $(hook deps "$1"); do
    if ! dep_ok "$d" "$2"; then printf '%s' "$d"; return 0; fi
  done
  return 1
}

satisfied() { # already done on this machine, by marker or by looking
  [ "$MS_FORCE" = 1 ] && return 1
  [ -e "$(marker "$1")" ] && ! csv_has "$(hook flags "$1" | tr ' ' ',')" always && return 0
  hook check "$1"
}

question() {
  local q s
  q="$(hook desc "$1")"
  if has_hook sudo "$1"; then
    s="$(hook sudo "$1")"
    q="$q (runs sudo/$s as root)"
  fi
  printf '%s?' "$q"
}

plan() {
  local id flags dep
  log "Plan: answer once per step; nothing is changed until you have answered them all"
  for id in $MS_STEPS; do
    flags="$(hook flags "$id" | tr ' ' ',')"
    if csv_has "$MS_SKIP" "$id"; then set_status "$id" "skipped:--skip"; continue; fi
    if satisfied "$id"; then
      set_status "$id" already
      info "✓ $(hook desc "$id") (already done)"
      continue
    fi
    if [ -n "$MS_ONLY" ] && ! csv_has "$MS_ONLY" "$id"; then set_status "$id" "skipped:not selected"; continue; fi
    if [ "$MS_UNATTENDED" = 1 ] && csv_has "$flags" interactive; then
      set_status "$id" "skipped:needs a person (--unattended)"; continue
    fi
    if csv_has "$flags" display && ! has_display && [ "${MS_FORCE_DISPLAY:-}" != 1 ]; then
      set_status "$id" "skipped:no graphical session"; continue
    fi
    if dep=$(unmet_dep "$id" plan); then
      set_status "$id" "skipped:needs $dep"
      info "- $(hook desc "$id"): skipped, needs $dep"
      continue
    fi
    if ask "$(question "$id")"; then set_status "$id" planned; else set_status "$id" "skipped:declined"; fi
  done
}

execute() {
  local id dep rc
  for id in $MS_STEPS; do
    [ "$(get_status "$id")" = planned ] || continue
    if dep=$(unmet_dep "$id" run); then
      set_status "$id" "skipped:needs $dep"
      warn "skipping \"$id\": it needs \"$dep\", which did not complete"
      continue
    fi
    log "$(hook desc "$id")"
    set +e
    ( set -euo pipefail; hook run "$id" )
    rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
      set_status "$id" "failed"
      err "step \"$id\" failed (exit $rc)"
      continue
    fi
    if [ "$MS_DRY" = 1 ]; then
      set_status "$id" dry
    else
      set_status "$id" "done"
      if ! csv_has "$(hook flags "$id" | tr ' ' ',')" always; then
        mkdir -p "$MS_STATE_DIR/done"
        : > "$(marker "$id")"
      fi
    fi
  done
}

# Does any planned step run a sudo/ script?
needs_sudo() {
  local id
  for id in $MS_STEPS; do
    [ "$(get_status "$id")" = planned ] && has_hook sudo "$id" && return 0
  done
  return 1
}

print_summary() {
  local id s
  log "Summary"
  for id in $MS_STEPS; do
    s="$(get_status "$id")"
    case "$s" in
      done)     printf '    %sdone%s      %s\n' "$C_GREEN" "$C_OFF" "$id" ;;
      dry)      printf '    would run %s\n' "$id" ;;
      already)  printf '    already   %s\n' "$id" ;;
      failed)   printf '    %sFAILED%s    %s\n' "$C_RED" "$C_OFF" "$id" ;;
      skipped:*) printf '    skipped   %s (%s)\n' "$id" "${s#skipped:}" ;;
      *)        printf '    %s   %s\n' "$s" "$id" ;;
    esac
  done
}

list_steps() {
  local id
  for id in $MS_STEPS; do
    printf '%-20s needs: %-45s %s\n' "$id" "$(hook deps "$id" | tr ' ' ',')" "$(hook desc "$id")"
  done
}
