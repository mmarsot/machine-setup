# Portable configuration for the agent tools. These tools rewrite their own
# config (Claude Code and the axi `setup hooks` edit settings.json, for example),
# so Home Manager must not own them as read-only symlinks. Each file is seeded
# once instead: created if missing, never overwritten, and for JSON merged
# underneath what is already there. scripts/seed-file.sh does the work and keeps
# every file private to its owner (mode 600, an existing file keeps its mode),
# because these tools store credentials in them.
{ config, lib, pkgs, ... }:
let
  home = config.home.homeDirectory;

  seed = mode: target: source: lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.bash}/bin/bash ${../scripts/seed-file.sh} ${mode} "${target}" "${source}" ${pkgs.jq}/bin/jq
  '';
in
{
  home.activation = {
    seedClaudeSettings = seed "json" "${home}/.claude/settings.json" ../config/claude/settings.json;
    seedClaudeKeybindings = seed "json" "${home}/.claude/keybindings.json" ../config/claude/keybindings.json;
    seedNoMistakesConfig = seed "copy" "${home}/.no-mistakes/config.yaml" ../config/no-mistakes/config.yaml;
    seedHerdrConfig = seed "copy" "${home}/.config/herdr/config.toml" ../config/herdr/config.toml;
    # Node comes from the (read-only) Nix store, so npm globals need a writable
    # prefix. ~/.local keeps every agent binary in ~/.local/bin, which also
    # resolves in non-interactive shells and systemd units. npm later appends
    # registry auth tokens to this file, hence mode 600.
    seedNpmrc = seed "copy" "${home}/.npmrc" (pkgs.writeText "npmrc" "prefix=${home}/.local\n");
  };
}
