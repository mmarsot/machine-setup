# sudo scripts

Every change to the system layer that needs root lives here as a script. `setup.sh` runs one only after the owner answers yes to its prompt (or passes `--yes`), and the guided Claude Code session runs them only after asking the owner. Nothing in this repository calls `sudo` anywhere else.

| Script | What it changes |
|---|---|
| `apt-prereqs.sh` | installs `curl`, `git`, `ca-certificates` with apt |
| `install-nix.sh` | installs Nix with the Determinate Systems installer |
| `install-chrome.sh` | installs Google Chrome from Google's `.deb` (which also adds Google's apt repository for updates) |
| `install-bitwarden.sh` | installs the Bitwarden desktop app from Bitwarden's official `.deb` |

Each script must be run as root (`sudo ./sudo/<name>.sh`), is idempotent, and prints what it does.
