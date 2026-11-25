{ config, ... }:
{
  programs.bash = {
    enable = true;
    enableCompletion = true;

    # Runs for every bash startup that reads ~/.bashrc, before the
    # interactive-only part. The env file is fetched from the vault by
    # setup.sh (scripts/vault-env.sh); no secret is ever written here.
    bashrcExtra = ''
      # Terminals opened before the first re-login still need PATH and FM_*.
      if [ -r "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh" ]; then
        # shellcheck disable=SC1091
        . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"
      fi

      # shellcheck disable=SC1091
      [ -r "$HOME/.config/machine-setup/load-env.sh" ] && . "$HOME/.config/machine-setup/load-env.sh"
    '';
  };

  # One loader, shared with setup.sh, kept in the repo (scripts/load-env.sh).
  home.file.".config/machine-setup/load-env.sh".source = ../scripts/load-env.sh;

  home.sessionPath = [
    "$HOME/.local/bin" # claude, herdr, treehouse, no-mistakes, npm globals
  ];

  home.sessionVariables = {
    FM_BACKEND = "herdr";
    FM_HOME = "${config.home.homeDirectory}/firstmate";
  };
}
