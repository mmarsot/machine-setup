#!/usr/bin/env bash
# scripts/vault-env.sh (the safe paste of the Bitwarden note): validation, hidden
# input, mode 600, names-only output, replace confirmation. Every run uses a
# throwaway HOME; the real home directory and vault are never touched.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
command -v jq >/dev/null || { echo "jq is required for this test"; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required for this test"; exit 1; }

echo "vault-env"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
home="$work/home"
mkdir -p "$home"
env_file="$work/config/env"

mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
exists() { if [ -e "$1" ]; then echo yes; else echo no; fi; }

# paste STDIN_TEXT: run the script with piped input (no terminal); output in $out, status in $rc.
paste() {
  out="$(printf '%s' "$1" | env HOME="$home" XDG_CONFIG_HOME="$home/.config" MS_ENV_FILE="$env_file" \
    "$REPO_ROOT/scripts/vault-env.sh" 2>&1)"
  rc=$?
}

# tty_run STEPS_JSON: run the script on a pseudo-terminal, typing the given
# [wait-for-text, text-to-send] steps. Prints everything the terminal showed;
# the exit status is the last line, as "rc=N".
tty_run() {
  HOME="$home" XDG_CONFIG_HOME="$home/.config" MS_ENV_FILE="$env_file" STEPS="$1" CMD="${2:-$REPO_ROOT/scripts/vault-env.sh}" \
    python3 -I -c '
import json, os, pty, select, subprocess, sys, time
steps = json.loads(os.environ["STEPS"])
master, slave = pty.openpty()
proc = subprocess.Popen([os.environ["CMD"]], stdin=slave, stdout=slave, stderr=slave, close_fds=True, start_new_session=True)
os.close(slave)
seen = b""
mark = 0
def pump(timeout):
    global seen
    r, _, _ = select.select([master], [], [], timeout)
    if not r:
        return True
    try:
        data = os.read(master, 4096)
    except OSError:
        return False
    if not data:
        return False
    seen += data
    return True
alive = True
for wait_for, send in steps:
    deadline = time.time() + 10
    while alive and wait_for.encode() not in seen[mark:] and time.time() < deadline:
        alive = pump(0.2)
    mark = len(seen)
    time.sleep(0.2)  # let the script switch the terminal mode before typing
    os.write(master, send.encode())
while alive:
    alive = pump(0.5)
    if proc.poll() is not None and not alive:
        break
proc.wait(timeout=10)
sys.stdout.write(seen.decode(errors="replace"))
print("\nrc=%d" % proc.returncode)
'
}
tty_rc() { printf '%s' "$1" | tail -n 1 | sed 's/^rc=//'; }

good=$'# runtime tokens\n\nexport FOO_TOKEN=abc123\r\nexport B_TOKEN=\'x y\'\nexport C_TOKEN="q v"   \n  # indented comment\n'

echo "  piped paste"
rm -rf "$work/config"
paste "$good"
assert_eq "a valid paste is saved" "$rc" "0"
assert_eq "env file has mode 600" "$(mode_of "$env_file")" "600"
assert_eq "carriage returns are stripped" "$(grep -c $'\r' "$env_file")" "0"
assert_eq "the file sources cleanly" "$(bash -c ". '$env_file'; echo \$FOO_TOKEN/\$B_TOKEN/\$C_TOKEN")" "abc123/x y/q v"
assert_contains "variable names are printed" "$out" "FOO_TOKEN"
assert_contains "all names are printed" "$out" "C_TOKEN"
assert_contains "the count is printed" "$out" "Saved 3 variable(s)"
assert_not_contains "values are never printed" "$out" "abc123"
assert_not_contains "quoted values are never printed" "$out" "x y"
assert_eq "no temporary file is left behind" "$(find "$work/config" -type f | wc -l | tr -d ' ')" "1"

rm -rf "$work/config"
paste "export LAST=1"
assert_eq "a paste without a final newline is saved" "$rc" "0"
assert_eq "a final newline is added" "$(tail -c1 "$env_file" | od -An -c | tr -d ' ')" '\n'

echo "  rejected pastes"
reject() { # reject NAME TEXT: refused, nothing written, secret text never printed
  rm -rf "$work/config"
  paste "$2"
  assert_eq "$1: refused" "$rc" "1"
  assert_eq "$1: nothing is written" "$(exists "$env_file")" "no"
  assert_contains "$1: says Nothing was saved" "$out" "Nothing was saved"
}
reject "a stray command" $'export OK=1\nrm -rf SECRETWORD\n'
assert_contains "the line number is reported" "$out" "line 2"
assert_not_contains "the rejected line is never echoed" "$out" "SECRETWORD"
reject "a command substitution" $'export A=$(echo SECRETWORD)\n'
assert_not_contains "its value is never echoed" "$out" "SECRETWORD"
reject "a backtick" $'export A=`echo hi`\n'
reject "a variable expansion in double quotes" $'export A="$HOME"\n'
reject "a chained command" $'export A=1; echo hi\n'
reject "a missing export" $'FOO=bar\n'
reject "two words" $'export A=one two\n'
reject "an unterminated quote" $'export A="oops\n'
reject "an invalid name" $'export 1A=x\n'
rm -rf "$work/config"; paste ''
assert_eq "an empty paste is refused" "$rc" "1"
assert_contains "an empty paste is called out" "$out" "Nothing was pasted"
assert_eq "an empty paste writes nothing" "$(exists "$env_file")" "no"
reject "comments only" $'# just a comment\n\n'
reject "recovery codes" $'export GITHUB_RECOVERY_CODES=aaaa-bbbb\n'
assert_contains "refusal explains why" "$out" "never go in the environment"
assert_not_contains "refused values are never printed" "$out" "aaaa-bbbb"
for key in BITWARDEN_DUAL_AUTH TOTP_SEED my_2fa_code MASTER_PASSWORD BACKUP_CODES; do
  reject "$key" "export $key=x"
done
reject "one bad line among good ones" $'export A=1\nexport B=$(id)\nexport C=3\n'
assert_contains "every bad line is listed" "$out" "line 2"

echo "  replacing an existing file"
rm -rf "$work/config"; paste "export OLD=1"
paste $'n\nexport NEW=1\n'
assert_eq "declining keeps the file" "$rc" "10"
assert_eq "the old content is kept" "$(cat "$env_file")" "export OLD=1"
paste $'\nexport NEW=1\n'
assert_eq "Enter alone means no" "$rc" "10"
paste $'y\nexport NEW=1\n'
assert_eq "confirming replaces the file" "$rc" "0"
assert_eq "the new content is written" "$(cat "$env_file")" "export NEW=1"
assert_eq "the replaced file has mode 600" "$(mode_of "$env_file")" "600"
paste $'y\nexport BAD=$(id)\n'
assert_eq "a bad paste over an existing file fails" "$rc" "1"
assert_eq "the existing file survives a bad paste" "$(cat "$env_file")" "export NEW=1"

echo "  ~/.bashrc loading"
rm -rf "$work/config" "$home/.bashrc"
paste "export A=1"
assert_contains "a missing loader is called out" "$out" "does not load it yet"
echo '[ -r "$HOME/.config/machine-setup/load-env.sh" ] && . "$HOME/.config/machine-setup/load-env.sh"' > "$home/.bashrc"
rm -rf "$work/config"; paste "export A=1"
assert_contains "a bashrc with the loader is accepted" "$out" "through ~/.bashrc"
assert_not_contains "no warning then" "$out" "does not load it yet"

echo "  terminal paste (pseudo-terminal)"
secret='tty-secret-value-7781'
# Control: a plain `cat` on the same terminal harness does echo what is typed.
cat_out="$(tty_run "[[\"\", \"export X=$secret\\n\\u0004\"]]" /bin/cat)"
assert_contains "the harness shows echoed input (control)" "$cat_out" "$secret"

rm -rf "$work/config"
steps="[[\"Ctrl-D\", \"# note\\nexport TTY_TOKEN=$secret\\nexport OTHER='a b'\\n\\u0004\"]]"
tty_out="$(tty_run "$steps")"
assert_eq "a terminal paste is saved" "$(tty_rc "$tty_out")" "0"
assert_not_contains "pasted values are not echoed to the terminal" "$tty_out" "$secret"
assert_not_contains "quoted values are not echoed either" "$tty_out" "a b"
assert_contains "the instructions name the note" "$tty_out" 'Secure Note "bashrc"'
assert_contains "names are printed" "$tty_out" "TTY_TOKEN"
assert_contains "the count is printed" "$tty_out" "Saved 2 variable(s)"
assert_eq "the file holds the pasted lines" "$(grep -c "$secret" "$env_file")" "1"
assert_eq "the file has mode 600" "$(mode_of "$env_file")" "600"

rm -rf "$work/config"
steps="[[\"Ctrl-D\", \"export BAD=\$(echo $secret)\\n\\u0004\"], [\"Paste again\", \"y\\n\"], [\"then Ctrl-D\", \"export GOOD_TOKEN=1\\n\\u0004\"]]"
tty_out="$(tty_run "$steps")"
assert_eq "retrying after a rejection saves the good paste" "$(tty_rc "$tty_out")" "0"
assert_contains "the rejection is explained" "$tty_out" "line 1"
assert_not_contains "the rejected paste is not echoed" "$tty_out" "$secret"
assert_eq "only the good paste is saved" "$(cat "$env_file")" "export GOOD_TOKEN=1"

rm -rf "$work/config"
steps="[[\"Ctrl-D\", \"export BAD=\$(echo $secret)\\n\\u0004\"], [\"Paste again\", \"n\\n\"]]"
tty_out="$(tty_run "$steps")"
assert_eq "skipping after a rejection exits 10" "$(tty_rc "$tty_out")" "10"
assert_eq "skipping writes nothing" "$(exists "$env_file")" "no"
assert_not_contains "a skipped paste is not echoed" "$tty_out" "$secret"

echo "  loader"
# The loader accepts a 600 file and refuses a looser one.
printf 'LOADED_VAR=yes\n' > "$work/loadme"; chmod 600 "$work/loadme"
assert_eq "loader loads a mode-600 file (env var)" "$(MS_ENV_FILE="$work/loadme" bash -c ". '$REPO_ROOT/scripts/load-env.sh'; echo \${LOADED_VAR:-no}" 2>/dev/null)" "yes"
chmod 644 "$work/loadme"
assert_eq "loader refuses a world-readable file" "$(MS_ENV_FILE="$work/loadme" bash -c ". '$REPO_ROOT/scripts/load-env.sh'; echo \${LOADED_VAR:-no}" 2>/dev/null)" "no"

echo "bitwarden-extension"
profile="$work/chrome/Default"
ext_id=nngceckbapebfimnlniiiahkandclblb
# steps() sources the step definitions in a subshell with the profile under test.
in_steps() { ( export MS_CHROME_PROFILE="$profile" HOME="$home"; . "$REPO_ROOT/lib/ui.sh"; . "$REPO_ROOT/lib/steps.sh"; "$@" ); }
detected() { if in_steps check_bitwarden_extension; then echo yes; else echo no; fi; }

rm -rf "$work/chrome"; mkdir -p "$profile"
assert_eq "an empty profile has no extension" "$(detected)" "no"
mkdir -p "$profile/Extensions/someotherextensionidxxxxxxxxxxxx/1.0_0"
assert_eq "another extension does not count" "$(detected)" "no"
mkdir -p "$profile/Extensions/$ext_id/2024.1.0_0"
assert_eq "the extension's folder counts" "$(detected)" "yes"
assert_eq "an installed extension makes the step already done" \
  "$(in_steps satisfied bitwarden-extension && echo yes || echo no)" "yes"

# run: the Web Store opens only when the extension is missing.
mkdir -p "$work/fakebin"
cat > "$work/fakebin/google-chrome-stable" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_LOG:?}"
FAKE
chmod +x "$work/fakebin/google-chrome-stable"
run_ext() { ( export PATH="$work/fakebin:$PATH" FAKE_LOG="$work/chrome.log" MS_EXTENSION_WAIT=0 MS_CHROME_PROFILE="$profile" HOME="$home"
  . "$REPO_ROOT/lib/ui.sh"; . "$REPO_ROOT/lib/steps.sh"; run_bitwarden_extension </dev/null 2>&1 ); }
rm -f "$work/chrome.log"
out="$(run_ext)"
assert_contains "an installed extension is reported" "$out" "already in this Chrome profile"
sleep 0.5
assert_eq "an installed extension never opens the Web Store" "$(exists "$work/chrome.log")" "no"
rm -rf "$profile/Extensions/$ext_id"
out="$(run_ext)"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$work/chrome.log" ] && break; sleep 0.3; done
assert_contains "a missing extension opens the Web Store" "$(cat "$work/chrome.log" 2>/dev/null)" "chromewebstore.google.com/detail/bitwarden-password-manager/$ext_id"
assert_contains "and says what to click" "$out" "Add to Chrome"

echo "engine: a skipped step"
out="$( MS_STATE_DIR="$work/state" HOME="$home" bash -c '
  . "'"$REPO_ROOT"'/lib/ui.sh"; . "'"$REPO_ROOT"'/lib/steps.sh"
  MS_STEPS=fake; MS_RUN_DIR="$(mktemp -d)"
  desc_fake() { echo fake; }; deps_fake() { :; }; flags_fake() { echo skippable; }; run_fake() { return 10; }
  set_status fake planned; execute >/dev/null 2>&1
  get_status fake; echo; [ -e "$(marker fake)" ] && echo marked || echo unmarked' )"
assert_contains "exit 10 from a skippable step is a skip, not a failure" "$out" "skipped:skipped by you"
assert_contains "a skipped step is not marked done" "$out" "unmarked"
out="$( MS_STATE_DIR="$work/state" HOME="$home" bash -c '
  . "'"$REPO_ROOT"'/lib/ui.sh"; . "'"$REPO_ROOT"'/lib/steps.sh"
  MS_STEPS=fake; MS_RUN_DIR="$(mktemp -d)"
  desc_fake() { echo fake; }; deps_fake() { :; }; flags_fake() { :; }; run_fake() { return 10; }
  set_status fake planned; execute >/dev/null 2>&1
  get_status fake' )"
assert_eq "exit 10 from any other step is a failure" "$out" "failed"

finish
