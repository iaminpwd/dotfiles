#!/usr/bin/env bash
# TFLint role이 호출 CWD의 .tflint.d 대신 사용자 전역 plugin dir에 설치하는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo '[WARNING] SKIP: ansible-playbook 필요 (TFLint plugin dir 회귀)'
  exit 0
fi
if ! command -v tflint >/dev/null 2>&1; then
  echo '[WARNING] SKIP: tflint 필요 (TFLint plugin dir 회귀)'
  exit 0
fi

export ANSIBLE_HOME="$TMP/ansible-home"
export ANSIBLE_LOCAL_TEMP="$TMP/local"
export ANSIBLE_REMOTE_TEMP="$TMP/remote"

mkdir -p "$TMP/ansible/roles/tflint/tasks" "$TMP/stow/tflint" "$TMP/home" "$TMP/work/.tflint.d/plugins"

cp "$ROOT/ansible/roles/tflint/tasks/main.yml" "$TMP/ansible/roles/tflint/tasks/main.yml"

cat >"$TMP/stow/tflint/.tflint.hcl" <<'HCL'
plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
HCL

cat >"$TMP/play.yml" <<YAML
- hosts: localhost
  gather_facts: false
  connection: local
  vars:
    ansible_env:
      HOME: "$TMP/home"
      PATH: "$PATH"
  roles:
    - role: tflint
YAML

(
  cd "$TMP/work"
  HOME="$TMP/home" ANSIBLE_ROLES_PATH="$TMP/ansible/roles" ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/out" 2>&1
) || {
  cat "$TMP/out"
  exit 1
}

PLUGIN_REL="github.com/terraform-linters/tflint-ruleset-aws/0.49.0/tflint-ruleset-aws"
if [ ! -f "$TMP/home/.tflint.d/plugins/$PLUGIN_REL" ]; then
  echo 'FAIL: global TFLint plugin was not installed under HOME'
  echo "local plugin path:"
  find "$TMP/work/.tflint.d/plugins" -type f -maxdepth 8 -print 2>/dev/null || true
  cat "$TMP/out"
  exit 1
fi

if [ -f "$TMP/work/.tflint.d/plugins/$PLUGIN_REL" ]; then
  echo 'FAIL: TFLint role installed plugin into caller-local .tflint.d'
  exit 1
fi

echo 'PASS: TFLint role pins plugin installation to HOME global directory'
