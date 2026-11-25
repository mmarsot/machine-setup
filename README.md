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

To load your shell environment (for example `CLAUDE_CODE_OAUTH_TOKEN`) from Bitwarden, create a **Secure Note** named `bashrc` before running the script. Put plain bash lines in its *Notes* field:

```sh
export CLAUDE_CODE_OAUTH_TOKEN=...
```

The `vault-env` step writes the note to `~/.config/machine-setup/env` (mode 600) and every new shell loads it. It works on Bitwarden's free plan.

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
