# Command-line tools from Nix. Fast-moving agent tools (Claude Code, the axi
# tools, herdr, treehouse, no-mistakes) are NOT here: they install through their
# own installers or npm and update themselves (see lib/steps.sh).
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    jq
    curl
    ripgrep
    delta
    htop
    tmux # fallback backend for firstmate when herdr is not wanted
    uv # python tooling, and `uvx` for MCP servers
    nodejs # runtime for the npm-installed axi tools
    python3 # firstmate record export
    perl # firstmate process-event helpers
    bitwarden-cli # `bw`: fetches the env file from the vault
  ];
}
