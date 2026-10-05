#!/usr/bin/env bash
# zsh 기본 셸 변경 실패가 Ansible 성공으로 숨겨지지 않는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo '[WARNING] SKIP: ansible-playbook 필요 (zsh shell failure 회귀)'
  exit 0
fi

export ANSIBLE_HOME="$TMP/ansible"
export ANSIBLE_LOCAL_TEMP="$TMP/local"
export ANSIBLE_REMOTE_TEMP="$TMP/remote"

python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import json
import sys

root, tmp = map(Path, sys.argv[1:])
source = (root / "ansible/roles/zsh/tasks/main.yml").read_text()
marker = "- name: 사용자의 기본 셸을 zsh로 변경"
start = source.index(marker)
task = source[start:].rstrip() + "\n"
(tmp / "tasks.yml").write_text("---\n" + task)

# ':'가 들어간 계정명은 Linux useradd/usermod 계열에서 유효한 사용자명이 아니다.
# 실제 production task를 그대로 import하고 입력만 실패하도록 만들어, mutating task가
# 실패를 Ansible 성공으로 바꾸는지 확인한다.
(tmp / "play.yml").write_text(json.dumps([{
    "name": "Zsh login-shell failure propagation regression",
    "hosts": "localhost",
    "connection": "local",
    "gather_facts": False,
    "vars": {
        "ansible_user_id": "invalid:user:name",
        "zsh_path": {"stdout": "/bin/sh"},
    },
    "tasks": [{
        "name": "Import actual login-shell mutation task",
        "ansible.builtin.import_tasks": str(tmp / "tasks.yml"),
    }],
}]))
PY

status=0
ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/out" 2>&1 || status=$?

if [ "$status" -eq 0 ]; then
  cat "$TMP/out"
  echo 'FAIL: zsh 기본 셸 변경 실패가 failed_when:false 때문에 성공으로 숨겨졌습니다.'
  exit 1
fi

grep -Eq 'invalid|user|name|usermod|useradd' "$TMP/out" || {
  cat "$TMP/out"
  echo 'FAIL: 의도한 사용자 변경 실패가 아닌 다른 원인으로 play가 실패했습니다.'
  exit 1
}

echo 'PASS: zsh 기본 셸 변경 실패가 Ansible 실패로 전파됨'
