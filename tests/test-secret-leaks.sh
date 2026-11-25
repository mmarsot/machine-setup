#!/usr/bin/env bash
# No secret may reach the Nix store or a world-readable file, and the env file
# must reach every kind of shell. Covers: the shared detector, the pre-build scan
# that stops Nix copying a secret into the store, the audit that reports what
# already leaked, the seeded config files' modes, the env loader in login and
# non-login shells, and the Nix files themselves. All fake values are built at run
# time from pieces, so no token-shaped string sits in this file. Every run uses
# throwaway directories; the real home directory and the real store are never read.
# The single quotes hold shell text that other shells expand later; ls -i reads one inode.
# shellcheck disable=SC2016,SC2012
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
command -v jq >/dev/null || { echo "jq is required for this test"; exit 1; }

echo "secret leaks"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
# Fake secrets, assembled from pieces.
fake_pat="github""_pat_$(printf 'A%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22)"
fake_value="fake-value-${RANDOM}${RANDOM}"
fake_a="fake-value-alpha-${RANDOM}"
fake_b="fake-value-beta-${RANDOM}"

echo "  detector"
# shellcheck source=lib/secrets.sh
. "$REPO_ROOT/lib/secrets.sh"
leaky="$work/leaky"
{
  printf 'export DEMO_%s=%s\n' TOKEN "$fake_value"
  printf '  DEMO_%s="%s"\n' PASSWORD "$fake_value"
  printf '# a comment\nexport FM_HOME="$HOME/firstmate"\n'
  printf 'export SHORT_%s=abc\n' TOKEN
  printf 'export INDIRECT_%s=$OTHER_VARIABLE\n' TOKEN
  printf 'url=%s\n' "$fake_pat"
} > "$leaky"
assert_eq "counts only the lines that look like secrets" "$(ms_secret_count "$leaky")" "3"
names="$(ms_secret_names "$leaky" | tr '\n' ' ')"
assert_eq "lists the variable names" "$names" "DEMO_PASSWORD DEMO_TOKEN "
all_out="$(ms_secret_count "$leaky"; ms_secret_names "$leaky"; ms_files_with_secrets "$leaky")"
assert_not_contains "never prints a value" "$all_out" "$fake_value"
assert_not_contains "never prints a token" "$all_out" "$fake_pat"
assert_eq "an ordinary file has none" "$(ms_secret_count "$REPO_ROOT/home/default.nix")" "0"
assert_eq "an unreadable path counts as none" "$(ms_secret_count "$work/missing")" "0"

echo "  what Nix would copy into the store"
assert_eq "this repository is clean" "$(ms_scan_store_bound "$REPO_ROOT")" ""

plain="$work/plain-dir"
mkdir -p "$plain/home" "$plain/.git"
echo '{ }' > "$plain/home/ok.nix"
assert_eq "a clean directory passes" "$(ms_scan_store_bound "$plain"; echo "rc=$?")" "rc=0"
printf 'export DEMO_%s=%s\n' TOKEN "$fake_value" > "$plain/home/notes.txt"
out="$(ms_scan_store_bound "$plain")"; rc=$?
assert_eq "a directory that is not a git checkout is scanned whole" "$rc" "1"
assert_eq "the offending file is named" "$out" "home/notes.txt"
assert_not_contains "its content is not shown" "$out" "$fake_value"

gitdir="$work/git-dir"
mkdir -p "$gitdir/home"
git -C "$gitdir" init -q
echo '{ }' > "$gitdir/home/ok.nix"
git -C "$gitdir" add . >/dev/null
printf 'export DEMO_%s=%s\n' TOKEN "$fake_value" > "$gitdir/untracked.txt"
assert_eq "an untracked file is not copied by Nix, so it is not flagged" "$(ms_scan_store_bound "$gitdir"; echo "rc=$?")" "rc=0"
printf 'export DEMO_%s=%s\n' TOKEN "$fake_value" >> "$gitdir/home/ok.nix"
out="$(ms_scan_store_bound "$gitdir")"; rc=$?
assert_eq "an uncommitted edit of a tracked file is flagged" "$rc" "1"
assert_eq "the edited file is named" "$out" "home/ok.nix"

echo "  the home step refuses to build with a secret in its source"
bin="$work/bin"; mkdir -p "$bin" "$work/gen"
cat > "$bin/nix" <<EOF
#!/usr/bin/env bash
echo "\$*" > "$work/nix-called"
echo "$work/gen"
EOF
printf '#!/usr/bin/env bash\ntouch "%s/activated"\n' "$work" > "$work/gen/activate"
chmod +x "$bin/nix" "$work/gen/activate"
run_home_in() { # run_home_in REPO [ENV=VALUE...]: the home step against a fake repository
  local repo="$1"; shift
  rm -f "$work/nix-called" "$work/activated"
  env "$@" HOME="$work/h" PATH="$bin:$PATH" MS_REPO="$repo" SRC="$REPO_ROOT" bash -c '
    set -euo pipefail
    . "$SRC/lib/ui.sh"; . "$SRC/lib/secrets.sh"; . "$SRC/lib/steps.sh"
    MS_DRY=0
    run_home' 2>&1
}
mkdir -p "$work/h" "$work/repos"
cp -r "$plain" "$work/repos/leaky"; cp -r "$plain" "$work/repos/clean"
rm "$work/repos/clean/home/notes.txt"
out="$(run_home_in "$work/repos/leaky" MS_X=1)"; rc=$?
assert_eq "a secret in the source stops the step" "$rc" "1"
assert_eq "Nix is never run" "$(test -e "$work/nix-called" && echo yes || echo no)" "no"
assert_contains "the file is named" "$out" "home/notes.txt"
assert_contains "the reason is given" "$out" "every account"
assert_not_contains "the value is not shown" "$out" "$fake_value"
out="$(run_home_in "$work/repos/clean" MS_X=1)"; rc=$?
assert_eq "a clean source builds and activates" "$rc" "0"
assert_eq "Nix ran" "$(test -e "$work/nix-called" && echo yes || echo no)" "yes"
assert_eq "the generation was activated" "$(test -e "$work/activated" && echo yes || echo no)" "yes"

echo "  audit of a machine that already leaked"
# A fake Home Manager state: generation 1 holds a secret, generation 2 is clean.
mk_state() { # mk_state DIR: a fake home with an empty fake store
  local h="$1"
  rm -rf "$h"; mkdir -p "$h/.local/state/nix/profiles" "$h/store" "$h/gens/g1" "$h/gens/g2"
}
mk_gen() { # mk_gen DIR N STOREFILE: generation N shows STOREFILE as its .bashrc
  mkdir -p "$1/files$2"
  ln -s "$3" "$1/files$2/.bashrc"
  ln -s "$1/files$2" "$1/gens/g$2/home-files"
  ln -s "$1/gens/g$2" "$1/.local/state/nix/profiles/home-manager-$2-link"
}
h="$work/state"
mk_state "$h"
mkdir "$h/store/aaa-bashrc" "$h/store/bbb-bashrc"
printf '# clean\nexport DEMO_%s=%s\nexport OTHER_%s="%s"\n' TOKEN "$fake_a" SECRET "$fake_b" > "$h/store/aaa-bashrc/f"
printf '# clean\n[ -r x ] && . x\n' > "$h/store/bbb-bashrc/f"
mk_gen "$h" 1 "$h/store/aaa-bashrc/f"
mk_gen "$h" 2 "$h/store/bbb-bashrc/f"
mkdir -p "$work/stubs"
cat > "$work/stubs/nix-store" <<'EOF'
#!/usr/bin/env bash
# Stand-in for nix-store --verify-path: the paths listed in $STUB_MODIFIED fail the way Nix reports it.
[ "$1" = --verify-path ] || exit 2
case " $STUB_MODIFIED " in *" $2 "*) echo "path '$2' was modified! expected hash 'sha256:x', got 'sha256:y'" >&2; exit 1 ;; esac
exit 0
EOF
chmod +x "$work/stubs/nix-store"
audit() { # audit HOME [ENV=VALUE...]: output in $out, status in $rc
  local home="$1"; shift
  out="$(env -i HOME="$home" PATH="$work/stubs:$PATH" XDG_STATE_HOME="$home/.local/state" XDG_CONFIG_HOME="$home/.config" \
    MS_STORE_DIR="$home/store" "$@" "$REPO_ROOT/scripts/audit-secrets.sh" 2>&1)"
  rc=$?
}
before="$(cd "$h" && find . -type f -o -type l | sort | xargs -I{} sh -c 'ls -ld "{}"; cat "{}" 2>/dev/null' | cksum)"
audit "$h" STUB_MODIFIED=""
assert_eq "a leaked secret in an old generation fails the audit" "$rc" "1"
assert_contains "the leaking store file is named" "$out" "$h/store/aaa-bashrc/f"
assert_contains "the generation is named" "$out" "generation(s): 1"
assert_contains "the line count is given" "$out" "2 line(s) look like secrets"
assert_contains "the variable names are given" "$out" "DEMO_TOKEN OTHER_SECRET"
assert_not_contains "no secret value is printed" "$out" "$fake_a"
assert_not_contains "no other secret value is printed" "$out" "$fake_b"
assert_not_contains "the clean generation is not reported" "$out" "bbb-bashrc"
assert_contains "the cleanup says to rotate" "$out" "revoke it at its provider"
assert_contains "the cleanup names the env file" "$out" "scripts/vault-env.sh"
assert_contains "the cleanup expires old generations" "$out" "--delete-generations old"
assert_contains "the cleanup collects garbage" "$out" "nix-collect-garbage"
assert_not_contains "no repair step when nothing was modified" "$out" "--repair-path"
after="$(cd "$h" && find . -type f -o -type l | sort | xargs -I{} sh -c 'ls -ld "{}"; cat "{}" 2>/dev/null' | cksum)"
assert_eq "the audit changes nothing" "$after" "$before"

# The shape of the real incident: the current store file was edited in place.
rm "$h/.local/state/nix/profiles/home-manager-1-link"
audit "$h" STUB_MODIFIED="$h/store/bbb-bashrc"
assert_eq "a store path Nix says was modified fails the audit" "$rc" "1"
assert_contains "the modified path is reported" "$out" "was modified after it was built"
assert_contains "the repair command names the path" "$out" "sudo nix-store --repair-path $h/store/bbb-bashrc"
assert_not_contains "no secret advice without a secret" "$out" "revoke it at its provider"

audit "$h" STUB_MODIFIED=""
assert_eq "a clean machine passes" "$rc" "0"
assert_eq "and the audit is silent" "$out" ""

audit "$work/no-such-home"
assert_eq "a machine without Home Manager passes" "$rc" "0"

mkdir -p "$h/.config/machine-setup"
printf 'export A_%s=%s\n' TOKEN "$fake_value" > "$h/.config/machine-setup/env"
chmod 644 "$h/.config/machine-setup/env"
audit "$h"
assert_eq "a world-readable env file fails the audit" "$rc" "1"
assert_contains "the env file is named with its mode" "$out" "has mode 644"
assert_contains "the fix is given" "$out" "chmod 600"
assert_not_contains "its value is not printed" "$out" "$fake_value"
chmod 600 "$h/.config/machine-setup/env"
audit "$h"
assert_eq "a mode-600 env file passes" "$rc" "0"

echo "  setup.sh reports it on start"
sandbox="$work/sandbox"
mk_state "$sandbox"
mkdir "$sandbox/store/aaa-bashrc"
printf 'export DEMO_%s=%s\n' TOKEN "$fake_a" > "$sandbox/store/aaa-bashrc/f"
mk_gen "$sandbox" 1 "$sandbox/store/aaa-bashrc/f"
out="$(HOME="$sandbox" XDG_CONFIG_HOME="$sandbox/.config" XDG_STATE_HOME="$sandbox/.local/state" MS_STORE_DIR="$sandbox/store" \
  PATH="$work/stubs:$PATH" MS_FORCE_DISPLAY=1 "$REPO_ROOT/setup.sh" --dry-run --only apt-prereqs 2>&1)"
assert_contains "setup.sh prints the audit report before the plan" "$out" "$sandbox/store/aaa-bashrc/f"
assert_contains "and ends with a reminder" "$out" "secrets are exposed on this machine"
assert_not_contains "without the value" "$out" "$fake_a"
out="$(setup_in_sandbox --dry-run --only apt-prereqs)"
assert_not_contains "a clean machine gets no report" "$out" "secrets are exposed"
assert_contains "no env file: the summary says where tokens go" "$out" "scripts/vault-env.sh"
assert_contains "and not to paste them into ~/.bashrc" "$out" "never paste them into ~/.bashrc"

echo "  seeded config files stay private"
seed() { "$REPO_ROOT/scripts/seed-file.sh" "$@" 2>&1; }
src="$work/seed-src"; mkdir -p "$src"
echo '{"model":"opus","theme":"dark","nested":{"a":1}}' > "$src/settings.json"
echo 'prefix=/x' > "$src/npmrc"
sd="$work/seed"; mkdir -p "$sd"
seed copy "$sd/new/.npmrc" "$src/npmrc" >/dev/null
assert_eq "a new copy has mode 600" "$(mode_of "$sd/new/.npmrc")" "600"
assert_eq "its new parent directory is private" "$(mode_of "$sd/new")" "700"
assert_eq "and has the content" "$(cat "$sd/new/.npmrc")" "prefix=/x"
echo 'registry_token=kept' > "$sd/.npmrc"; chmod 644 "$sd/.npmrc"
seed copy "$sd/.npmrc" "$src/npmrc" >/dev/null
assert_eq "an existing copy is not overwritten" "$(cat "$sd/.npmrc")" "registry_token=kept"
assert_eq "but a world-readable one is made private" "$(mode_of "$sd/.npmrc")" "600"
seed json "$sd/s1/settings.json" "$src/settings.json" >/dev/null
assert_eq "new JSON has mode 600" "$(mode_of "$sd/s1/settings.json")" "600"
assert_eq "new JSON has the content" "$(jq -c . "$sd/s1/settings.json")" '{"model":"opus","theme":"dark","nested":{"a":1}}'
echo '{"model":"mine","env":{"FAKE":"x"},"nested":{"b":2}}' > "$sd/s2.json"; chmod 600 "$sd/s2.json"
seed json "$sd/s2.json" "$src/settings.json" >/dev/null
assert_eq "a merge keeps the owner's values and fills the rest" "$(jq -cS . "$sd/s2.json")" '{"env":{"FAKE":"x"},"model":"mine","nested":{"a":1,"b":2},"theme":"dark"}'
assert_eq "a merged 600 file stays 600" "$(mode_of "$sd/s2.json")" "600"
cp "$sd/s2.json" "$sd/s3.json"; chmod 640 "$sd/s3.json"
seed json "$sd/s3.json" "$src/settings.json" >/dev/null
assert_eq "a merged group-readable file is made private" "$(mode_of "$sd/s3.json")" "600"
inode_before="$(ls -i "$sd/s3.json" | cut -d' ' -f1)"
seed json "$sd/s3.json" "$src/settings.json" >/dev/null
assert_eq "the merge rewrites in place, not through a new file" "$(ls -i "$sd/s3.json" | cut -d' ' -f1)" "$inode_before"
echo 'not json' > "$sd/bad.json"
msg="$(seed json "$sd/bad.json" "$src/settings.json")"; rc=$?
assert_eq "invalid JSON is left alone" "$(cat "$sd/bad.json")" "not json"
assert_eq "without failing the activation" "$rc" "0"
assert_contains "and says so" "$msg" "is not valid JSON"

echo "  the env file reaches every kind of shell"
# The loader line exactly as Home Manager writes it into ~/.profile and ~/.bashrc
# (checked against a real build of the module in a Nix container).
loader='[ -r "$HOME/.config/machine-setup/load-env.sh" ] && . "$HOME/.config/machine-setup/load-env.sh"'
hh="$work/shellhome"; mkdir -p "$hh/.config/machine-setup"
cp "$REPO_ROOT/scripts/load-env.sh" "$hh/.config/machine-setup/load-env.sh"
printf 'export AGENT_%s=%s\n' TOKEN "$fake_value" > "$hh/.config/machine-setup/env"; chmod 600 "$hh/.config/machine-setup/env"
# The generated files, in the shape Home Manager writes them (seen on a real machine).
printf '%s\n' "$loader" > "$hh/.profile"
printf '%s\n' '[[ -f ~/.profile ]] && . ~/.profile' '[[ -f ~/.bashrc ]] && . ~/.bashrc' > "$hh/.bash_profile"
printf '%s\n' "$loader" '[[ $- == *i* ]] || return' 'echo past-the-interactive-guard' > "$hh/.bashrc"
sh_env() { env -i HOME="$hh" PATH=/usr/bin:/bin TERM=dumb "$@" 2>&1; }
probe='echo "value=${AGENT_TOKEN:-unset}"'
assert_contains "bash -lc (an agent started from a login shell) sees it" "$(sh_env bash -lc "$probe")" "value=$fake_value"
assert_not_contains "that shell stopped at the interactive guard, as non-interactive shells do" "$(sh_env bash -lc "$probe")" "past-the-interactive-guard"
assert_contains "an interactive shell sees it" "$(sh_env bash -ic "$probe")" "value=$fake_value"
if command -v dash >/dev/null; then
  assert_contains "sh -lc (dash reads only .profile) sees it" "$(sh_env dash -lc "$probe")" "value=$fake_value"
fi
chmod 644 "$hh/.config/machine-setup/env"
assert_contains "a world-readable env file is still refused" "$(sh_env bash -lc "$probe")" "value=unset"
chmod 600 "$hh/.config/machine-setup/env"
# Why the token was missing on the desktop: an export placed after the guard is
# seen by interactive shells only.
printf '%s\n' '[[ $- == *i* ]] || return' "export AGENT_$(printf TOKEN)=$fake_value" > "$hh/.bashrc"
rm "$hh/.profile"
assert_contains "(control) an export after the guard is invisible to bash -lc" "$(sh_env bash -lc "$probe")" "value=unset"

finish
