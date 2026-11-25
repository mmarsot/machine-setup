{ ... }:
{
  programs.git = {
    enable = true;
    # Personal identity is asked for by setup.sh and kept out of the repo.
    includes = [{ path = "~/.config/git/identity"; }];
    # gh as the credential helper for GitHub, resolved through PATH so there is
    # one gh (the Nix one) and no hard-coded /usr/bin/gh. The empty first value
    # resets any helper inherited from a system config. `credential.helper=store`
    # is never configured.
    settings.credential = {
      "https://github.com".helper = [ "" "!gh auth git-credential" ];
      "https://gist.github.com".helper = [ "" "!gh auth git-credential" ];
    };
  };

  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = false; # configured above, by PATH
    settings = {
      git_protocol = "https";
      prompt = "enabled";
      aliases.co = "pr checkout";
    };
  };
}
