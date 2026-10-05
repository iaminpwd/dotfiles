#!/usr/bin/env bash
# packages -> stow 순서에서 macOS/BSD readlink 환경의 드리프트 판정이 정확한지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo '[WARNING] SKIP: ansible-playbook 필요 (stow readlink ordering 회귀)'
  exit 0
fi

export ANSIBLE_HOME="$TMP/ansible"
export ANSIBLE_LOCAL_TEMP="$TMP/local"
export ANSIBLE_REMOTE_TEMP="$TMP/remote"

ROLE="$TMP/repo/ansible/roles/stow"
PKG="$TMP/repo/stow/demo"
HOME_DIR="$TMP/home"
FAKEBIN="$TMP/fakebin"
mkdir -p "$ROLE/tasks" "$PKG/.config/demo" "$HOME_DIR" "$FAKEBIN"
printf 'managed\n' >"$PKG/.config/demo/config"

# macOS 기본 BSD readlink처럼 -f를 지원하지 않되 plain readlink는 동작하게 한다.
cat >"$FAKEBIN/readlink" <<'STUB'
#!/bin/sh
if [ "${1:-}" = "-f" ]; then
  echo 'readlink: illegal option -- f' >&2
  exit 1
fi
exec /usr/bin/readlink "$@"
STUB
chmod +x "$FAKEBIN/readlink"

python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import json
import sys

root, tmp = map(Path, sys.argv[1:])
source = (root / "ansible/roles/stow/tasks/main.yml").read_text()

start_marker = "- name: 심볼릭 링크 드리프트(변경 필요 여부) 사전 판정"
end_marker = "- name: GNU Stow 를 통해 홈 디렉토리에 심볼릭 링크 적용"
start = source.index(start_marker)
end = source.index(end_marker, start)
subset = source[start:end].rstrip() + "\n"
(tmp / "tasks.yml").write_text("---\n" + subset)

play = [{
    "name": "Stow cross-component ordering regression",
    "hosts": "localhost",
    "connection": "local",
    "gather_facts": False,
    "environment": {
        "PATH": str(tmp / "fakebin") + ":/usr/bin:/bin",
    },
    "vars": {
        "role_path": str(tmp / "repo/ansible/roles/stow"),
        "ansible_env": {"HOME": str(tmp / "home")},
        "stow_dirs": {"files": [{"path": str(tmp / "repo/stow/demo")}]},
    },
    "tasks": [
        {
            "name": "Import actual stow drift detector",
            "ansible.builtin.import_tasks": str(tmp / "tasks.yml"),
        },
        {
            "name": "Assert missing target is detected as drift",
            "ansible.builtin.assert": {
                "that": [
                    "stow_drift_check.results | length == 1",
                    "stow_drift_check.results[0].stdout | trim == '1'",
                ],
                "fail_msg": "stow drift detector treated BSD readlink -f failure as no drift",
            },
        },
    ],
}]
(tmp / "play.yml").write_text(json.dumps(play))
PY

status=0
ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/out" 2>&1 || status=$?
if [ "$status" -ne 0 ]; then
  cat "$TMP/out"
  exit "$status"
fi

echo 'PASS: stow drift detector works without GNU readlink -f'
