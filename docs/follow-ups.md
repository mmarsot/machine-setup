# Follow-ups

Notes on optional extras that are out of scope for the first version. None of them is built; each would be its own skippable step, off by default, and must respect STRATEGY.md.

- **macOS target.** Add `aarch64-darwin` / `x86_64-darwin` to `systems` in `flake.nix` and a `homeConfigurations` entry for it, plus nix-darwin or a Brewfile for Chrome and Bitwarden. CI already evaluates the shared modules for `aarch64-darwin`; `setup.sh` refuses to run on macOS until the desktop-app steps exist there.
- **Docker Engine.** Used by several projects. Would be a `sudo/install-docker.sh` (apt, `docker` group) offered by the guided session when a project needs it.
- **Visage face login on Ubuntu.** Only when a webcam exists, and only changing PAM after a successful face test. Ubuntu only; never on macOS.
- **Other agent harnesses** (Codex, Pi, OpenCode, CodeGraph). Installed by the guided session on request through their own installers or npm.
- **Project toolchains** (Rust via rustup, awscli2, google-cloud-sdk, rclone, build essentials). Added per project by the guided session, preferably as Home Manager packages.
- **Voice dictation, local models (Ollama), Hugging Face.** Optional dev-adjacent tooling, off by default.
- **One-line bootstrap.** The repository is public, so a short script fetched with `curl` could install git and clone it; today the README Install block installs git and clones the repository before running `setup.sh`.
- **GNOME preferences** (dark style, keyboard layout, tiling). Per-OS by design; could be a `dconf` step.
- **Bitwarden login autostart.** `setup.sh` does not write an autostart entry: the Bitwarden app manages `~/.config/autostart/bitwarden.desktop` itself and overwrites any other entry. Upstream's entry starts the binary directly (`/opt/Bitwarden/bitwarden-app --autostart`) rather than the `/opt/Bitwarden/bitwarden` launcher, so at login the app runs without the launcher's `ulimit -c 0` and forced X11. A fix belongs upstream; setup.sh itself still opens the app through the launcher.
- **`--force` with `--only`.** `--force` makes every step unsatisfied, so unselected dependencies that are already done count as "not selected" and a `--only` step is skipped with "needs <dep>" (for example `./setup.sh --only home --force`). Today the docs list the dependency chain or point at `scripts/vault-env.sh`; a fix would apply `--force` only to the selected steps.
- **Read-only `/nix/store`.** A root edit through a Home Manager symlink (for example `sudo nano ~/.bashrc`) writes into the store, which every account can read; today `scripts/audit-secrets.sh` only detects it afterwards. Mounting `/nix/store` read-only for everything except the Nix daemon (a read-only bind mount, as NixOS does), through a `sudo/` script, would prevent it.
