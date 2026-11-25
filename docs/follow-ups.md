# Follow-ups

Notes on optional extras that are out of scope for the first version. None of them is built; each would be its own skippable step, off by default, and must respect STRATEGY.md.

- **macOS target.** Add `aarch64-darwin` / `x86_64-darwin` to `systems` in `flake.nix` and a `homeConfigurations` entry for it, plus nix-darwin or a Brewfile for Chrome and Bitwarden. CI already evaluates the shared modules for `aarch64-darwin`; `setup.sh` refuses to run on macOS until the desktop-app steps exist there.
- **Docker Engine.** Used by several projects. Would be a `sudo/install-docker.sh` (apt, `docker` group) offered by the guided session when a project needs it.
- **Visage face login on Ubuntu.** Only when a webcam exists, and only changing PAM after a successful face test. Ubuntu only; never on macOS.
- **Other agent harnesses** (Codex, Pi, OpenCode, CodeGraph). Installed by the guided session on request through their own installers or npm.
- **Project toolchains** (Rust via rustup, awscli2, google-cloud-sdk, rclone, build essentials). Added per project by the guided session, preferably as Home Manager packages.
- **Voice dictation, local models (Ollama), Hugging Face.** Optional dev-adjacent tooling, off by default.
- **Cleanup of this repository's bootstrap.** The private repository needs GitHub access before it can be cloned; a short public bootstrap script, or a release asset fetched with a token from the vault, could shorten step 1 of the README.
- **GNOME preferences** (dark style, keyboard layout, tiling). Per-OS by design; could be a `dconf` step.
