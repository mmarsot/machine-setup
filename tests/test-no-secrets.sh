#!/usr/bin/env bash
# No secret is ever committed: scan tracked files for token shapes and for the
# configuration mistakes the strategy forbids.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

echo "no-secrets"
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  files="$(git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard)"
else
  files="$(cd "$REPO_ROOT" && find . -type f -not -path './.git/*' | sed 's|^\./||')"
fi

# Token shapes: Anthropic, GitHub, AWS, Hugging Face, Google, Slack, private keys.
shapes='sk-ant-[A-Za-z0-9_-]{10,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gho_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|hf_[A-Za-z0-9]{30,}|AIza[0-9A-Za-z_-]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
hits="$(cd "$REPO_ROOT" && printf '%s\n' "$files" | grep -v '^tests/test-no-secrets.sh$' | xargs grep -nE "$shapes" 2>/dev/null)"
assert_eq "no token-shaped strings in tracked files" "$hits" ""

# Literal exports of secrets in dotfiles/scripts (a value after the =, not a variable).
lit="$(cd "$REPO_ROOT" && printf '%s\n' "$files" | grep -E '\.(nix|sh)$|^config/' | xargs grep -nE "^[[:space:]]*(export[[:space:]]+)?[A-Z0-9_]*(TOKEN|SECRET|PASSWORD|API_KEY|RECOVERY)[A-Z0-9_]*=['\"]?[A-Za-z0-9_+/=.-]{8,}" 2>/dev/null | grep -v 'tests/')"
assert_eq "no literal secret exports" "$lit" ""

store="$(cd "$REPO_ROOT" && printf '%s\n' "$files" | grep -E '\.(nix|sh|toml|yaml|json|md)$' | grep -v '^tests/' | xargs grep -nE 'helper *= *"?store|credential\.helper[ =]+store' 2>/dev/null | grep -v '^[^:]*:[0-9]*: *#')"
assert_eq "credential.helper=store is never configured" "$store" ""

secret_files="$(printf '%s\n' "$files" | grep -E '(^|/)(\.git-credentials|\.credentials\.json|auth\.json|hosts\.yml|\.claude\.json|\.env)$')"
assert_eq "no credential files are tracked" "$secret_files" ""

finish
