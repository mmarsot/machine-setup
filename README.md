# machine-setup

One script that sets up a fresh Ubuntu 26.04 machine for agentic development: Claude Code, firstmate, no-mistakes, herdr and the axi tools, on a Nix + Home Manager base, plus Google Chrome and Bitwarden. See [STRATEGY.md](STRATEGY.md) for the vision and scope.

## Install

The repository is public, so no GitHub login is needed. On the fresh machine, in a terminal:

```sh
sudo apt update && sudo apt install -y git
git clone https://github.com/mmarsot/machine-setup.git ~/machine-setup
~/machine-setup/setup.sh
```

Clone the whole repository: `setup.sh` uses the files next to it.

## What it does

- Asks yes or no for every step up front (Enter means yes), then installs what you accepted.
- Pauses for the logins only you can do: Chrome, Bitwarden, your git name and email, and GitHub (`gh auth login`, for private projects).
- Ends by starting Claude Code in `~/firstmate`, with a prompt that guides the rest of the configuration.
- Is safe to run again: steps already done are skipped, and nothing is ever updated.

Anything that needs root is a script in [`sudo/`](sudo/README.md), run only after your yes.

## Secrets (optional)

To load your shell environment (for example `CLAUDE_CODE_OAUTH_TOKEN`) into every shell, keep it in a Bitwarden **Secure Note** named `bashrc`, as plain bash lines in its *Notes* field:

```sh
# runtime tokens
export CLAUDE_CODE_OAUTH_TOKEN=...
```

The `vault-env` step asks you to log in through the Bitwarden desktop app or browser extension, open that note, copy its Notes and paste them into the terminal. Nothing you paste is displayed; press Enter then Ctrl-D to finish. It accepts only blank lines, `# comments` and `export NAME=value` lines (the value is one plain, `'single-quoted'` or `"double-quoted"` word), and rejects anything else with the line number, so you can fix the note and paste again, or skip the step. Variables named like recovery codes or master passwords are refused: keep those in the vault only.

The paste is written to `~/.config/machine-setup/env` (mode 600), and `~/.bashrc` and `~/.profile` load it, so interactive, login (`bash -lc`, `sh -lc`) and non-interactive bash shells all see it. Setup prints only the variable names it saved, never their values. To replace the file later, run `scripts/vault-env.sh`; it asks before overwriting.

### Never put a secret in `~/.bashrc`

Home Manager's `~/.bashrc` and `~/.profile` are read-only symlinks into `/nix/store`, which every account on the machine can read. Do not edit them, and above all not with `sudo` (`sudo nano ~/.bashrc` writes through the link and puts what you type into the store). Put tokens in `~/.config/machine-setup/env` with `scripts/vault-env.sh` instead.

Setup guards this in three ways:

- Before it builds the Home Manager configuration it scans what Nix would copy into the store (tracked files with their uncommitted edits, or every file when the checkout has no `.git`) and refuses to build if one looks like it holds a token. There is no override: a false alarm is fixed by changing the file.
- Every start of `setup.sh` runs `scripts/audit-secrets.sh`, which is read-only. It scans every file of every Home Manager generation, asks Nix whether any store path was modified after it was built, and checks the env file's mode. If it finds something it prints the file, the variable names (never a value) and the cleanup steps, and deletes nothing: revoke and reissue the exposed secrets, restore a modified store path with `sudo nix-store --repair-path <path>`, rebuild with `./setup.sh --force --only apt-prereqs,nix,home`, then `nix-env --profile ~/.local/state/nix/profiles/home-manager --delete-generations old` and `nix-collect-garbage`.
- Config files that tools later put credentials in (`~/.npmrc`, `~/.claude/settings.json` and the other seeded files) are created with mode 600, and an existing one that you own is made private to you (`chmod go-rwx`) on every activation.

## Options

```
./setup.sh --list           list the steps and what each needs
./setup.sh --yes            answer yes to every step
./setup.sh --dry-run        print every change without making any
./setup.sh --only a,b       only these steps
./setup.sh --skip a,b       everything except these steps
```

## Tests

```sh
tests/run.sh               # unit tests; no network, no changes
tests/docker.sh            # full unattended setup in a throwaway ubuntu:26.04 container
```
