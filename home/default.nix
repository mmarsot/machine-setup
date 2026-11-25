# Shared, platform-neutral base. Nothing here may assume Linux: OS-specific
# pieces belong behind `pkgs.stdenv.isLinux` / `isDarwin` or in a separate module.
{ ... }:
{
  imports = [
    ./packages.nix
    ./shell.nix
    ./git.nix
    ./agents.nix
  ];

  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  # Skip building the Home Manager manuals: setup time is the metric.
  manual = {
    manpages.enable = false;
    html.enable = false;
    json.enable = false;
  };
}
