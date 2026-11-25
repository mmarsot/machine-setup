<h1 align="center">machine-setup</h1>

<p align="center">
  <img src="assets/captain.png" height="72" alt="The captain">
  <img src="assets/first-mate.png" height="72" alt="The first mate">
  <img src="assets/crewmate.png" height="72" alt="A crewmate">
  <img src="assets/terminal.png" height="72" alt="A terminal">
  <img src="assets/anchor.png" height="72" alt="An anchor">
</p>

<p align="center"><b>One script turns a fresh Ubuntu 26.04 machine into a working agentic development environment.</b></p>

Install Ubuntu, run `setup.sh`, answer a few yes/no questions, and you end up in a Claude Code session that helps you configure the rest. The goal is the agent setup: [Claude Code](https://www.anthropic.com/claude-code), [firstmate](https://github.com/kunchenguid/firstmate) with [no-mistakes](https://github.com/kunchenguid/no-mistakes), [lavish and the axi tools](#what-gets-installed), and [herdr](https://herdr.dev). Google Chrome, Bitwarden and a few other tools come along, but they are extras. macOS is planned, not shipped yet. See [STRATEGY.md](STRATEGY.md) for the vision and scope.

## The idea

| | | |
|---|---|---|
| <img src="assets/captain.png" height="48" alt=""> | **You** | Talk to one agent. |
| <img src="assets/first-mate.png" height="48" alt=""> | **firstmate** | The agent you talk to. It dispatches the work. |
| <img src="assets/crewmate.png" height="48" alt=""> | **Crewmates** | Claude Code and other agents, each in its own worktree. |
| <img src="assets/terminal.png" height="48" alt=""> | **The terminal layer** | herdr, the axi tools, no-mistakes, lavish: what the crew works with. |
| <img src="assets/anchor.png" height="48" alt=""> | **The base** | Nix + Home Manager: the ground it all stands on. Chrome and Bitwarden are extras on top. |

```
        CORE                                   EXTRAS
  ┌──────────────────────────────────┐   ┌───────────────────────┐
  │ Claude Code · firstmate          │   │ Google Chrome         │
  │ no-mistakes · lavish · axi tools │   │ Bitwarden (+ browser  │
  │ herdr · treehouse                │   │ extension) · git, gh  │
  └──────────────────────────────────┘   └───────────────────────┘
          on a Nix + Home Manager base
```

## Install

On a fresh Ubuntu 26.04 machine you sit at. No GitHub login is needed, because the repository is public:

```sh
sudo apt update && sudo apt install -y git
git clone https://github.com/mmarsot/machine-setup.git ~/machine-setup
~/machine-setup/setup.sh
```

`setup.sh` is not a standalone file: it uses the flake, `config/` and `sudo/` next to it, so clone the whole repository (these two bootstrap commands are the only sudo outside [`sudo/`](sudo/README.md)).

What it does:

1. **Asks yes or no for every step up front** (Enter means yes). Declining a step also skips the steps that need it.
2. **Installs what you accepted.** Steps already done are recognised and skipped, so it is safe to run again. It never updates anything.
3. **Pauses for the logins only you can do**: Chrome, Bitwarden, git name and email, GitHub.
4. **Starts Claude Code in the firstmate clone** with a prompt that guides the rest of the configuration.

Anything that needs root is a script in [`sudo/`](sudo/README.md), run only after your yes.

**GitHub login comes later.** Nothing above needs a GitHub account. The `github-auth` step (`gh auth login`, in the browser, after Bitwarden so the extension can fill the form) is for your private projects, which the guided session clones afterwards.

### Options

```
./setup.sh --list           list the steps and what each needs
./setup.sh --yes            answer yes to every step
./setup.sh --unattended     --yes, and skip the steps that need a person (used by CI)
./setup.sh --dry-run        print every change without making any
./setup.sh --only a,b       only these steps
./setup.sh --skip a,b       everything except these steps
./setup.sh --force          run steps even when they look done
```

## What gets installed

| | Step | What |
|---|---|---|
| **Core** | `claude-code` | Claude Code, with its own installer |
| | `firstmate` | `git clone https://github.com/kunchenguid/firstmate ~/firstmate` |
| | `no-mistakes` | its own installer and daemon unit (plus a PATH drop-in so the daemon finds the Nix tools) |
| | `axi-tools` | `gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `tasks-axi`, `quota-axi` with npm, then each `setup hooks` |
| | `herdr`, `treehouse` | their own installers |
| | `home` | Home Manager from this flake: CLI tools, bash, git and gh config, ported agent config |
| **Extras** | `chrome`, `chrome-signin` | Google Chrome from Google's `.deb`, then opens it so you can sign in |
| | `bitwarden`, `bitwarden-signin`, `bitwarden-extension` | Bitwarden desktop from its `.deb`, login and biometric unlock, the Chrome extension |
| | `vault-env` | your shell environment from the vault, see [Secrets](#secrets) |
| | `git-identity`, `github-auth` | your git name and email (kept out of the repo), then `gh auth login` |
| **Base** | `apt-prereqs`, `nix` | `curl`, `git`, `ca-certificates`; Nix with flakes |
| **Last** | `launch` | Claude Code in `~/firstmate` with the configure-this-machine prompt |

`./setup.sh --list` prints every step with its dependencies, straight from the code. Fast-moving agent tools are never pinned and are not in Nix: they use their own installers or npm and update themselves.

## Secrets

Your shell environment (for example `CLAUDE_CODE_OAUTH_TOKEN`) lives in your Bitwarden vault, never in this repository. It works on Bitwarden's **free plan**, because it uses the *notes* of a Secure Note, not a file attachment.

1. In the Bitwarden app or web vault choose *New item* → *Secure Note*, name it **`bashrc`** (override with `MS_VAULT_ITEM`).
2. Paste plain bash lines into its *Notes* field:
   ```sh
   export CLAUDE_CODE_OAUTH_TOKEN=...
   ```
3. The `vault-env` step runs `bw get notes bashrc` and writes it to `~/.config/machine-setup/env` with mode 600; every new shell loads it. `bw` logs in once more here, because the CLI cannot use biometrics.

Quotes, comments, blank lines and Windows line endings are fine. A note must assign at least one variable, and one that defines a recovery code, a TOTP seed or a master password is refused: those stay in the vault.

## The guided Claude session

The last step starts Claude Code in `~/firstmate` with [`prompts/configure-machine.md`](prompts/configure-machine.md). It asks one yes or no question per topic and lets you skip any: OS authentication, GitHub, other agent harnesses (Codex, Pi, OpenCode), which projects to clone and their toolchains, crew dispatch, herdr or tmux, and how many agents the machine can run at once. It tells you what it will change first, and anything that needs sudo is a script in `sudo/` that it runs only with your permission. If the vault note defines `CLAUDE_CODE_OAUTH_TOKEN`, Claude counts as signed in.

## How it fits together

- `flake.nix`, `home/`: the shared, platform-neutral Home Manager base (packages, bash, git, gh). Inputs are not locked: the setup installs the latest stable of everything when it runs.
- `config/`: the portable configuration that is ported (Claude Code, no-mistakes, herdr). Tools rewrite these files, so Home Manager seeds each one once and never overwrites it. Machine state (sessions, caches, worktrees, logs) is never ported.
- `setup.sh`, `lib/`: the step engine. `scripts/`: the vault fetch and env loader. `prompts/`: the guided-session prompt.

## Tests

```sh
tests/run.sh               # engine, dependencies, vault guard, secret scan; no network, no changes
tests/docker.sh            # full unattended setup in a throwaway ubuntu:26.04 container, then verified
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs shellcheck, the unit tests, `nix flake check`, a macOS evaluation of the shared modules, the container run, and a native `./setup.sh --unattended` on an Ubuntu runner. The desktop-only steps (Chrome and Bitwarden sign-in, the extension) need a person and a display, so only `--dry-run` covers them. Optional extras that are deliberately not built yet are in [docs/follow-ups.md](docs/follow-ups.md).

## Credits

The illustrations are cropped from the banner of [firstmate](https://github.com/kunchenguid/firstmate) by Kun Chen, MIT licensed (Copyright (c) 2026 Kun Chen).
