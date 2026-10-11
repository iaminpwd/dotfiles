#!/usr/bin/env bash
# Same production Ansible zsh probe, two distinct safety contracts:
# --check must run the read-only probe; privileged shell selection must ignore
# a user-writable PATH entry. Generate the extracted task fixture just once.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export ANSIBLE_HOME="$TMP/ansible"
export ANSIBLE_LOCAL_TEMP="$TMP/local"
export ANSIBLE_REMOTE_TEMP="$TMP/remote"

mkdir -p "$TMP/user-bin"
cat >"$TMP/user-bin/zsh" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$TMP/user-bin/zsh"

python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import json
import sys

root, tmp = map(Path, sys.argv[1:])
source = (root / "ansible/roles/zsh/tasks/main.yml").read_text()
start = source.index("- name: 현재 설치된 zsh 경로 확인")
end = source.index("- name: 확인된 zsh 경로를 /etc/shells에 등록", start)
(tmp / "tasks.yml").write_text("---\n" + source[start:end].rstrip() + "\n")

def play(name, conditions, message):
    return [{
        "name": name,
        "hosts": "localhost",
        "connection": "local",
        "gather_facts": False,
        "tasks": [
            {"ansible.builtin.import_tasks": str(tmp / "tasks.yml")},
            {"ansible.builtin.assert": {"that": conditions, "fail_msg": message}},
        ],
    }]

(tmp / "check.yml").write_text(json.dumps(play(
    "Zsh check-mode path probe",
    ["not (zsh_path.skipped | default(false))", "(zsh_path.stdout | default('') | length) > 0"],
    "Read-only path probe was skipped in --check",
)))
(tmp / "privilege.yml").write_text(json.dumps(play(
    "Zsh privileged path probe",
    ["zsh_path.stdout == expected_zsh", "zsh_path.stdout != fake_zsh"],
    "zsh path probe trusted user-writable PATH for the account shell",
)))
PY

# Preserve the original check-mode test's fail-closed behavior when Ansible
# is absent: a missing validator is not a successful dry-run.
if ! PATH="$TMP/user-bin:$PATH" ansible-playbook -i localhost, "$TMP/check.yml" --check >"$TMP/check.out" 2>&1; then
  cat "$TMP/check.out"
  echo 'FAIL: zsh path probe did not run under Ansible --check' >&2
  exit 1
fi
echo 'PASS: zsh path read-only probe executes during Ansible check mode'

TRUSTED_PATH='/usr/bin:/bin'
EXPECTED_ZSH=$(PATH="$TRUSTED_PATH" command -v zsh 2>/dev/null || true)
if [ -z "$EXPECTED_ZSH" ]; then
  echo '[WARNING] SKIP: /usr/bin:/bin 에 시스템 zsh 없음 (권한 경계 사례만)'
  exit 0
fi

FAKE_ZSH="$TMP/user-bin/zsh"
if ! PATH="$TMP/user-bin:$PATH" ansible-playbook -i localhost, "$TMP/privilege.yml" \
  -e "expected_zsh=$EXPECTED_ZSH" -e "fake_zsh=$FAKE_ZSH" >"$TMP/privilege.out" 2>&1; then
  cat "$TMP/privilege.out"
  echo 'FAIL: privileged shell selection used user-writable PATH' >&2
  exit 1
fi
echo 'PASS: zsh privilege-boundary probe ignores user-writable PATH'
