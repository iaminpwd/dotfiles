#!/usr/bin/env bash
# ai_agent role 업데이트 시 저장소에서 삭제된 실행 스크립트 링크가 ~/.local/bin에 남지 않는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo '[WARNING] SKIP: ansible-playbook 필요 (ai_agent update prune 회귀)'
  exit 0
fi

export ANSIBLE_HOME="$TMP/ansible"
export ANSIBLE_LOCAL_TEMP="$TMP/local"
export ANSIBLE_REMOTE_TEMP="$TMP/remote"

mkdir -p "$TMP/repo/ansible/roles/ai_agent/tasks" "$TMP/repo/bin/utils" "$TMP/repo/bin" "$TMP/repo/contexts" "$TMP/home/.local/bin"
cp "$ROOT/bin/utils/safe-link-backup.sh" "$TMP/repo/bin/utils/safe-link-backup.sh"
cp "$ROOT/bin/utils/prune-orphan-agent-scripts.sh" "$TMP/repo/bin/utils/prune-orphan-agent-scripts.sh"

python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import json
import sys

root, tmp = map(Path, sys.argv[1:])
source = (root / "ansible/roles/ai_agent/tasks/main.yml").read_text()

start_marker = "- name: 에이전트 실행 스크립트 검색"
end_marker = "- name: 컨텍스트 도메인 디렉토리 목록 조회"
start = source.index(start_marker)
end = source.index(end_marker, start)
subset = source[start:end].rstrip() + "\n"
(tmp / "tasks.yml").write_text("---\n" + subset)

play = [{
    "name": "AI agent script update regression",
    "hosts": "localhost",
    "connection": "local",
    "gather_facts": False,
    "vars": {
        "role_path": str(tmp / "repo/ansible/roles/ai_agent"),
        "ansible_env": {"HOME": str(tmp / "home")},
    },
    "tasks": [{
        "name": "Import actual ai_agent script-link tasks",
        "ansible.builtin.import_tasks": str(tmp / "tasks.yml"),
    }],
}]
(tmp / "play.yml").write_text(json.dumps(play))
PY

cat >"$TMP/repo/bin/old-tool.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$TMP/repo/bin/old-tool.sh"

ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/first.out" 2>&1 || {
  cat "$TMP/first.out"
  exit 1
}

OLD_LINK="$TMP/home/.local/bin/old-tool.sh"
[ -L "$OLD_LINK" ] || {
  cat "$TMP/first.out"
  echo 'FAIL: 초기 버전의 old-tool.sh 링크가 생성되지 않았습니다.'
  exit 1
}

rm "$TMP/repo/bin/old-tool.sh"

# 공유 ~/.local/bin의 외부 broken symlink는 dotfiles 소유가 아니므로 보존해야 한다.
ln -s "$TMP/foreign/missing-tool.sh" "$TMP/home/.local/bin/foreign-tool.sh"

cat >"$TMP/repo/bin/new-tool.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$TMP/repo/bin/new-tool.sh"

ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/second.out" 2>&1 || {
  cat "$TMP/second.out"
  exit 1
}

[ -L "$TMP/home/.local/bin/new-tool.sh" ] || {
  cat "$TMP/second.out"
  echo 'FAIL: 업데이트된 new-tool.sh 링크가 생성되지 않았습니다.'
  exit 1
}

if [ -L "$OLD_LINK" ]; then
  cat "$TMP/second.out"
  echo 'FAIL: 저장소에서 삭제된 old-tool.sh의 고아 링크가 ~/.local/bin에 남았습니다.'
  exit 1
fi

[ -L "$TMP/home/.local/bin/foreign-tool.sh" ] || {
  cat "$TMP/second.out"
  echo 'FAIL: 외부 사용자 소유 broken symlink까지 삭제했습니다.'
  exit 1
}

echo 'PASS: ai_agent 업데이트가 저장소 소유 고아 링크만 정리하고 외부 링크는 보존함'
