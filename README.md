# machine-setup
Set up a fresh Ubuntu (later macOS) machine with the full development toolchain: a short setup script on a shared Nix + Home Manager base, then a guided Claude Code session. See [STRATEGY.md](STRATEGY.md) for the vision and scope.

## Usage

`setup.sh` is for a machine you sit at, run once, right after installing Ubuntu 26.04. It asks yes or no for every step up front, then installs what you accepted, then pauses for the logins only you can do.

### 1. Get the repository onto the machine

The repository is private, so GitHub has to know you before you can clone it. Either:

```sh
sudo apt update && sudo apt install -y git gh
gh auth login            # GitHub.com, HTTPS, "Login with a web browser"
gh repo clone mmarsot/machine-setup ~/machine-setup
```

or sign in to GitHub in the browser, download the repository as a ZIP, and unzip it to `~/machine-setup`. (These bootstrap commands are the only sudo outside this repository's `sudo/` scripts; they exist because the script cannot fetch itself.)

### 2. Run it

```sh
~/machine-setup/setup.sh
```

You are asked each question once, with Enter meaning yes. Declining a step also skips the steps that need it (no Chrome sign-in means no Bitwarden browser extension). Steps already done are recognised and skipped, so the script is safe to run again, and it never updates anything. The script ends by starting Claude Code in the firstmate clone with a prompt that helps you configure the rest of the machine.

| Step | What it does | Needs |
|---|---|---|
| `apt-prereqs` | `curl`, `git`, `ca-certificates` (sudo script) | |
| `chrome` | Google Chrome from Google's `.deb` (sudo script) | `apt-prereqs` |
| `bitwarden` | Bitwarden desktop from its `.deb` (sudo script) | `apt-prereqs` |
| `nix` | Nix, with flakes (sudo script) | `apt-prereqs` |
| `home` | Home Manager from this flake: CLI tools, bash, git and gh config, ported agent config | `nix` |
| `claude-code` | Claude Code, with its own installer | `apt-prereqs` |
| `axi-tools` | `gh-axi`, `chrome-devtools-axi`, `lavish-axi`, `tasks-axi`, `quota-axi` with npm, then each `setup hooks` | `home`, `claude-code` |
| `herdr`, `treehouse` | their own installers | `apt-prereqs` |
| `no-mistakes` | its own installer, then its own daemon unit (plus a PATH drop-in so the daemon finds the Nix tools) | `apt-prereqs`, `claude-code` |
| `firstmate` | `git clone https://github.com/kunchenguid/firstmate ~/firstmate` | `home`, `claude-code`, `axi-tools`, `treehouse`, `no-mistakes` |
| `git-identity` | asks for your git name and email, kept in `~/.config/git/identity`, not in the repo | `home` |
| `chrome-signin` | opens Chrome so you can sign in | `chrome` |
| `bitwarden-signin` | opens Bitwarden so you can log in and enable biometric unlock; starts it at login | `bitwarden` |
| `bitwarden-extension` | opens the Chrome Web Store page of the Bitwarden extension | `chrome-signin`, `bitwarden-signin` |
| `vault-env` | fetches your shell environment file from the vault | `home` |
| `github-auth` | `gh auth login`, after Bitwarden so the extension can fill the form | `home` |
| `launch` | starts Claude Code in `~/firstmate` with the configure-this-machine prompt | `firstmate`, `claude-code` |

`./setup.sh --list` prints the same table from the code.

### What only you can do

- **Google Chrome**: sign in to your Google account.
- **Bitwarden desktop**: log in with your email, master password and two-step code; in its settings turn on *Unlock with biometrics* and *Allow browser integration*.
- **Bitwarden extension**: click *Add to Chrome*, then choose *Unlock with biometrics* in its settings.
- **Vault environment file**: `bw` logs in once more, because the CLI cannot use biometrics. It works on Bitwarden's free plan, because it uses the *notes* of a Secure Note and never a file attachment. Create the note once, before running the step: in the Bitwarden app or web vault choose *New item* → type *Secure Note*, name it `bashrc` (that is the default; override it with `MS_VAULT_ITEM`), and paste plain bash lines into its *Notes* field, such as `export CLAUDE_CODE_OAUTH_TOKEN=...` (quotes, comments, blank lines and Windows line endings are all fine; the text is written as-is, minus carriage returns). The step runs `bw get notes bashrc` and writes it to `~/.config/machine-setup/env` with mode 600, and every new shell loads it. A note must assign at least one variable, and one that defines a recovery code, a TOTP seed or a master password is refused: those stay in the vault and never reach the environment.
- **GitHub**: `gh auth login` in the browser (Bitwarden fills the form when it is set up).
- **Claude Code**: sign in when it first starts. If the vault note defines `CLAUDE_CODE_OAUTH_TOKEN`, Claude counts as signed in and there is nothing to do; the launch step still checks that `claude` starts.

### Options

```
./setup.sh --yes            answer yes to every step
./setup.sh --unattended     --yes, and skip the steps that need a person (used by CI)
./setup.sh --dry-run        print every change without making any
./setup.sh --only a,b       only these steps
./setup.sh --skip a,b       everything except these steps
./setup.sh --force          run steps even when they look done
```

Anything that needs root is a script in [`sudo/`](sudo/README.md), run only after your yes (or `--yes`). The guided Claude Code session follows the same rule.

## How it fits together

- `flake.nix` and `home/`: the shared, platform-neutral Home Manager base (packages, bash, git, gh). Nothing in it assumes Linux, so a macOS configuration can be added later without restructuring. Inputs are not locked by a committed `flake.lock`: the setup installs the latest stable of everything when it runs.
- Fast-moving agent tools (Claude Code, the axi tools, herdr, treehouse, no-mistakes) are never pinned and are not in Nix: they use their own installers or npm and update themselves.
- `config/`: the portable configuration that is ported (Claude Code `settings.json` and `keybindings.json`, no-mistakes `config.yaml`, herdr `config.toml`). Tools rewrite these files, so Home Manager seeds each one once and never overwrites or symlinks it; the axi hooks are merged in by their own `setup hooks`. Machine state (sessions, caches, databases, worktrees, logs) is never ported.
- `setup.sh`, `lib/`: the step engine. `scripts/`: the vault fetch and env loader. `prompts/`: the guided-session prompt.

## Tests

```sh
tests/run.sh               # engine, dependencies, vault guard, secret scan; no network, no changes
tests/docker.sh            # full unattended setup in a throwaway ubuntu:26.04 container, then verified
```

CI (`.github/workflows/ci.yml`) runs shellcheck, the unit tests, `nix flake check` (which builds the whole Home Manager generation for a throwaway user), a macOS evaluation of the shared modules, the container run, and a native `./setup.sh --unattended` on an Ubuntu runner. The desktop-only steps (Chrome sign-in, Bitwarden sign-in and extension, the Bitwarden autostart entry) need a person and a display, so they are covered by `--dry-run` only. The systemd user unit that `no-mistakes daemon start` writes is likewise not exercised in the container.

Optional extras that are deliberately not built yet are listed in [docs/follow-ups.md](docs/follow-ups.md).
