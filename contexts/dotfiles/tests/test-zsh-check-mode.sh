#!/usr/bin/env bash
# ansible zsh role의 read-only zsh path probe가 --check에서도 실행되는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export ANSIBLE_HOME="$TMP/ansible"
export ANSIBLE_LOCAL_TEMP="$TMP/local"
export ANSIBLE_REMOTE_TEMP="$TMP/remote"

mkdir -p "$TMP/bin"
cat >"$TMP/bin/zsh" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$TMP/bin/zsh"
export PATH="$TMP/bin:$PATH"

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
    "name": "Zsh check-mode probe regression",
    "hosts": "localhost",
    "connection": "local",
    "gather_facts": False,
    "tasks": [
        {
            "name": "Import actual zsh path probe",
            "ansible.builtin.import_tasks": str(tmp / "tasks.yml"),
        },
        {
            "name": "Assert read-only probe ran during check mode",
            "ansible.builtin.assert": {
                "that": [
                    "not (zsh_path.skipped | default(false))",
                    "(zsh_path.stdout | default('') | length) > 0",
                ],
                "fail_msg": "zsh path probe was skipped in --check, so dependent shell changes are hidden from dry-run",
            },
        },
    ],
}]))
PY

if ! ansible-playbook -i localhost, "$TMP/play.yml" --check >"$TMP/out" 2>&1; then
  cat "$TMP/out"
  exit 1
fi

echo "PASS: zsh path read-only probe executes during Ansible check mode"
