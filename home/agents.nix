# Portable configuration for the agent tools. These tools rewrite their own
# config (Claude Code and the axi `setup hooks` edit settings.json, for example),
# so Home Manager must not own them as read-only symlinks. Each file is seeded
# once instead: created if missing, never overwritten, and for JSON merged
# underneath what is already there.
{ config, lib, pkgs, ... }:
let
  home = config.home.homeDirectory;

  seedCopy = target: source: lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "${target}" ]; then
      run mkdir -p "$(dirname "${target}")"
      run install -m 644 "${source}" "${target}"
    fi
  '';

  # Existing values win; the repo only fills in what is missing.
  seedJson = target: source: lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -e "${target}" ]; then
      run mkdir -p "$(dirname "${target}")"
      run install -m 644 "${source}" "${target}"
    elif tmp="$(mktemp)" && ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "${source}" "${target}" > "$tmp"; then
      run install -m 644 "$tmp" "${target}"
      rm -f "$tmp"
    else
      echo "machine-setup: ${target} is not valid JSON; leaving it untouched" >&2
      rm -f "$tmp"
    fi
  '';
in
{
  home.activation = {
    seedClaudeSettings = seedJson "${home}/.claude/settings.json" ../config/claude/settings.json;
    seedClaudeKeybindings = seedJson "${home}/.claude/keybindings.json" ../config/claude/keybindings.json;
    seedNoMistakesConfig = seedCopy "${home}/.no-mistakes/config.yaml" ../config/no-mistakes/config.yaml;
    seedHerdrConfig = seedCopy "${home}/.config/herdr/config.toml" ../config/herdr/config.toml;
    # Node comes from the (read-only) Nix store, so npm globals need a writable
    # prefix. ~/.local keeps every agent binary in ~/.local/bin, which also
    # resolves in non-interactive shells and systemd units.
    seedNpmrc = seedCopy "${home}/.npmrc" (pkgs.writeText "npmrc" "prefix=${home}/.local\n");
  };
}
