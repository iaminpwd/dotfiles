#!/usr/bin/env bash
# ansible tflint role이 --check에서 probe 결과 누락으로 fatal 나지 않는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export ANSIBLE_HOME="$TMP/ansible"
export ANSIBLE_LOCAL_TEMP="$TMP/local"
export ANSIBLE_REMOTE_TEMP="$TMP/remote"

HOME_DIR="$TMP/home"
SHIMS="$HOME_DIR/.local/share/mise/shims"
mkdir -p "$TMP/roles" "$SHIMS"
ln -s "$ROOT/ansible/roles/tflint" "$TMP/roles/tflint"

cat >"$SHIMS/tflint" <<'STUB'
#!/usr/bin/env sh
exit 0
STUB
chmod +x "$SHIMS/tflint"

cat >"$TMP/play.yml" <<YAML
- hosts: localhost
  gather_facts: false
  connection: local
  vars:
    ansible_env:
      HOME: "$HOME_DIR"
      PATH: "$PATH"
  roles:
    - role: tflint
YAML

if ! ansible-playbook -i localhost, "$TMP/play.yml" --check >"$TMP/out" 2>&1; then
  cat "$TMP/out"
  exit 1
fi

echo "PASS: TFLint role dry-run completes without losing probe result"
