# machine-setup Strategy

## Vision

<!-- vision: author-approved 2026-11-25 -->

`machine-setup` exists so that a fresh machine becomes its owner's working development machine in as little setup time as possible.
It serves one person, its owner, and turns a clean Ubuntu 26.04 machine, and later a Mac, into the toolchain they use every day: Claude Code, firstmate with no-mistakes, lavish and the axi tools, herdr, Google Chrome and Bitwarden.
It owns exactly one thing: the one-time path from a fresh machine to that working environment.

### Setup time comes before reproducibility

The setup is measured by how fast a fresh machine reaches a working toolchain.
Bit-for-bit reproducibility is not a goal: the setup installs the latest stable version of each tool at the moment it runs.
It runs once, at machine setup; after that the machine is the owner's to manage, and the setup does not update it.
Fast-moving agent tools - Claude Code, the axi tools, herdr, treehouse and no-mistakes - install through their own installers or npm and keep their own update commands; the setup never pins them.
Portable configuration of the tools it installs is ported, and machine state such as sessions, caches, databases, worktrees and logs never is.

### A short script, then a guided Claude session

A setup script installs the base everything else stands on: the shared command-line tools and dotfiles, Claude Code, and firstmate as a git clone with every tool it requires.
The script also owns the steps an agent should not drive: installing Google Chrome and signing in to it, and installing Bitwarden, its Chrome extension unlocked by biometrics, and the shell environment loaded from the vault.
The script ends by launching a Claude Code session in firstmate, prompted to help configure the fresh machine, and that session drives everything else.
The session covers the OS's own authentication, GitHub, which agent harnesses to install, which projects to clone and the development tools each of them needs, crew dispatch, herdr or tmux as the backend, and the machine's capacity for concurrent agents.
Every step, in the script or in the session, asks yes or no and can be skipped.
Steps follow their dependencies: declining a step skips the steps that need it, so no Chrome sign-in means no Bitwarden browser extension.
When Bitwarden is set up, logins the vault can fill, such as GitHub authentication, are prefilled from it; when it was skipped, they fall back to the interactive login.
GitHub authentication comes before any step that clones a private repository.
Every change that needs sudo is made by a script in this repository, which the guided session runs only after the owner gives permission.

### One shared base, OS differences allowed

The shared command-line base and dotfiles come from Nix and Home Manager and are the same on Ubuntu and macOS.
A tool or step may exist on one OS only when that OS calls for it: face recognition through visage is offered on Ubuntu and never on macOS, where the integrated biometrics are enough.
Visage is offered only when a webcam is available, and it changes PAM only after a successful face test.
Authentication and keyboard shortcuts are per-OS by design.
Desktop apps and system services stay with each platform's own channel - apt, snap or a vendor .deb on Ubuntu, and Homebrew casks on macOS - and Nix does not own the system layer.
Ubuntu is the target that must work today; macOS is a constraint every change respects, not yet a shipped target.

### Secrets live in Bitwarden, never in the repo

No token, password, recovery code or credential file is committed to this repository.
For now, one shell environment file kept in the vault carries the runtime tokens and is loaded at shell start; it is never written as literals into a tracked dotfile.
Two-factor recovery codes live in the vault only and never reach the environment.

### Each machine has a role

A machine is controlling only, remote only, or hybrid: remote while the owner is away and used at the desk when they are back.
The role is chosen before any firstmate step, and it decides what the setup installs.
A remote-only machine gets a minimal agent host: what firstmate needs to host a remote home, without the desktop steps.
A controlling or hybrid machine gets the full environment.
A hybrid machine runs two firstmate homes under two OS accounts: a remote account that the controlling machine drives, and the owner's own driver account used at the desk, which unlocks Bitwarden because the owner works at it.
A remote account never holds the owner's vault.
Secrets the driving machine can hand over for a single step reach the remote over SSH from the driver's store, on a pipe, and are never written to the remote's disk.
Tokens a remote account must keep come as one environment file copied from Bitwarden onto it at setup, so it never keeps a vault unlocked, and every token in that file can be revoked on its own if the machine is compromised.
A remote or hybrid machine's unattended base - never sleeping, key-only SSH, signing in after a restart - comes from kunchenguid/headless, and machine-setup builds on it rather than redoing it.
For a remote home, the controlling machine provisions and manages it, so the setup configures none of it.
The setup neither migrates nor scripts firstmate's data/ and config/; configuring firstmate is left to the owner in the guided session.

### Scope

machine-setup is not a NixOS configuration, not a fleet or multi-user provisioning tool, not a backup system, and not an ongoing configuration manager.
It starts from an already-installed Ubuntu; installing the operating system, dual boot included, is not its job.
It does not make a machine headless; that is kunchenguid/headless's job.
It does not carry firstmate's records between machines, and keeping several driver homes in sync on project data is not addressed for now.
Laptop-only hardware is out: the ScreenPad stack is specific and installs by hand from its own repository, and the laptop's GPU driver does not belong here.
Non-development apps are out, and so is VS Code.
Optional dev-adjacent tooling, such as voice dictation, local models and extra cloud SDKs, is off by default.

A change aligns when it shortens the path from a fresh machine to a working toolchain, adds a skippable step with sensible conditions, keeps the shared base the same on Ubuntu and macOS, or moves a step out of the script into the guided session where an agent handles it better.
A change should be resisted when it commits a secret, pins a self-updating agent tool, adds a step that cannot be skipped, runs a sudo change outside a repository script or without the owner's permission, gives a remote account the owner's vault, turns the one-time setup into an updater or configuration manager, ports machine state, scripts or migrates firstmate's own configuration, puts desktop steps on a remote-only machine, duplicates what headless sets up, or adds laptop-only hardware, VS Code or non-development tooling.
