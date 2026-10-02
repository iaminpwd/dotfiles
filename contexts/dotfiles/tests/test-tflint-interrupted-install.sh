#!/usr/bin/env bash
# 중단된 TFLint 플러그인 설치가 0바이트 파일을 남겨도 role 재실행으로 복구되는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo '[WARNING] SKIP: ansible-playbook 필요 (TFLint interrupted-install 회귀)'
  exit 0
fi
if ! command -v tflint >/dev/null 2>&1; then
  echo '[WARNING] SKIP: tflint 필요 (TFLint interrupted-install 회귀)'
  exit 0
fi

export ANSIBLE_HOME="$TMP/ansible-home"
export ANSIBLE_LOCAL_TEMP="$TMP/local"
export ANSIBLE_REMOTE_TEMP="$TMP/remote"

mkdir -p "$TMP/ansible/roles/tflint/tasks" "$TMP/stow/tflint" "$TMP/home"
cp "$ROOT/ansible/roles/tflint/tasks/main.yml" "$TMP/ansible/roles/tflint/tasks/main.yml"

cat >"$TMP/stow/tflint/.tflint.hcl" <<'HCL'
plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
HCL

PLUGIN_REL="github.com/terraform-linters/tflint-ruleset-aws/0.49.0/tflint-ruleset-aws"
BROKEN="$TMP/home/.tflint.d/plugins/$PLUGIN_REL"
mkdir -p "$(dirname "$BROKEN")"
: >"$BROKEN"
chmod 0755 "$BROKEN"

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

HOME="$TMP/home" ANSIBLE_ROLES_PATH="$TMP/ansible/roles" ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/out" 2>&1 || {
  cat "$TMP/out"
  exit 1
}

if [ ! -s "$BROKEN" ]; then
  echo 'FAIL: interrupted zero-byte TFLint plugin was treated as already installed'
  cat "$TMP/out"
  exit 1
fi

HOME="$TMP/home" tflint --chdir="$TMP/stow/tflint" --config "$TMP/stow/tflint/.tflint.hcl" >/dev/null 2>&1 || {
  echo 'FAIL: recovered TFLint plugin cannot be loaded'
  exit 1
}

echo 'PASS: TFLint role repairs zero-byte plugin artifacts left by interrupted install'
