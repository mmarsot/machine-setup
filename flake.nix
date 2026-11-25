{
  description = "machine-setup: shared Nix + Home Manager base for a fresh development machine";

  # Inputs are deliberately not pinned by a committed flake.lock: this repository
  # runs once on a fresh machine and installs the latest stable of everything
  # (see STRATEGY.md). setup.sh passes --no-write-lock-file, so nothing is
  # written back into the checkout.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      # Linux is the shipped target. The modules under ./home are platform
      # neutral, so adding "aarch64-darwin" / "x86_64-darwin" here (plus a
      # Homebrew layer for the desktop apps) needs no restructuring.
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forSystems = nixpkgs.lib.genAttrs systems;

      mkHome = { system, username, homeDirectory }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [
            ./home
            { home = { inherit username homeDirectory; }; }
          ];
        };
    in
    {
      lib = { inherit mkHome; };

      # The configuration setup.sh activates for the person running it. It reads
      # USER, HOME and the current system from the environment, so it exists only
      # under `--impure` (pure evaluation, e.g. `nix flake check`, sees none).
      homeConfigurations = nixpkgs.lib.optionalAttrs (builtins ? currentSystem) {
        default = mkHome {
          system = builtins.currentSystem;
          username = builtins.getEnv "USER";
          homeDirectory = builtins.getEnv "HOME";
        };
      };

      # `nix flake check` builds the whole Home Manager generation for a
      # throwaway user, which proves the modules evaluate and every package
      # resolves, without touching any real home directory.
      checks = forSystems (system: {
        home = (mkHome {
          inherit system;
          username = "ci";
          homeDirectory = "/home/ci";
        }).activationPackage;
      });

      formatter = forSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
