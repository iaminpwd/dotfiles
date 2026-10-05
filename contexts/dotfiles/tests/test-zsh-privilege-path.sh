#!/usr/bin/env bash
# zsh 경로 probe가 사용자 writable PATH를 신뢰해 privileged shell 설정으로 넘기지 않는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo '[WARNING] SKIP: ansible-playbook 필요 (zsh privilege PATH 회귀)'
  exit 0
fi

TRUSTED_PATH="/usr/bin:/bin"
EXPECTED_ZSH=$(PATH="$TRUSTED_PATH" command -v zsh 2>/dev/null || true)
if [ -z "$EXPECTED_ZSH" ]; then
  echo '[WARNING] SKIP: /usr/bin:/bin 에 시스템 zsh 없음'
  exit 0
fi

mkdir -p "$TMP/user-bin"
cat >"$TMP/user-bin/zsh" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$TMP/user-bin/zsh"
FAKE_ZSH="$TMP/user-bin/zsh"

export ANSIBLE_HOME="$TMP/ansible"
export ANSIBLE_LOCAL_TEMP="$TMP/local"
export ANSIBLE_REMOTE_TEMP="$TMP/remote"

python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import json
import sys

root, tmp = map(Path, sys.argv[1:])
source = (root / "ansible/roles/zsh/tasks/main.yml").read_text()

start_marker = "- name: 현재 설치된 zsh 경로 확인"
end_marker = "- name: 확인된 zsh 경로를 /etc/shells에 등록"
start = source.index(start_marker)
end = source.index(end_marker, start)
probe_task = source[start:end].rstrip() + "\n"

(tmp / "tasks.yml").write_text("---\n" + probe_task)
(tmp / "play.yml").write_text(json.dumps([{
    "name": "Zsh privilege PATH regression",
    "hosts": "localhost",
    "connection": "local",
    "gather_facts": False,
    "tasks": [
        {
            "name": "Import actual zsh path probe",
            "ansible.builtin.import_tasks": str(tmp / "tasks.yml"),
        },
        {
            "name": "Assert privileged shell input ignores user-writable PATH",
            "ansible.builtin.assert": {
                "that": [
                    "zsh_path.stdout == expected_zsh",
                    "zsh_path.stdout != fake_zsh",
                ],
                "fail_msg": "zsh path probe trusted a user-writable PATH entry that is later written to /etc/shells and the account shell",
            },
        },
    ],
}]))
PY

status=0
PATH="$TMP/user-bin:$PATH" ansible-playbook -i localhost, "$TMP/play.yml"   -e "expected_zsh=$EXPECTED_ZSH" -e "fake_zsh=$FAKE_ZSH" >"$TMP/out" 2>&1 || status=$?

if [ "$status" -ne 0 ]; then
  cat "$TMP/out"
  exit "$status"
fi

echo 'PASS: zsh privilege-boundary probe ignores user-writable PATH'
