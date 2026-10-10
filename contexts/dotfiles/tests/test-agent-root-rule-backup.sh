#!/usr/bin/env bash
# ai_agent role의 루트 AGENTS.md/CLAUDE.md 링크를 설치할 때 기존 사용자
# 파일과 외부 symlink를 복구 가능하게 보존하고 재실행은 멱등이어야 한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ANSIBLE_HOME="$TMP/ansible-cache"

FIXTURE="$TMP/fake-dotfiles"
mkdir -p "$FIXTURE/ansible/roles/ai_agent" "$FIXTURE/contexts/dotfiles" "$FIXTURE/bin/utils"
cp "$ROOT/bin/utils/safe-link-backup.sh" "$FIXTURE/bin/utils/"
printf 'managed skill\n' >"$FIXTURE/contexts/dotfiles/SKILL.md"
printf 'keep user AGENTS\n' >"$FIXTURE/AGENTS.md"
printf 'keep user CLAUDE\n' >"$TMP/claude-user.md"
ln -s "$TMP/claude-user.md" "$FIXTURE/CLAUDE.md"

# 실제 Ansible role에서 백업과 링크 태스크를 그대로 추출하여 격리된
# fake-dotfiles에 실행한다. 태스크가 삭제·역전되거나 계약이 바뀌면 실패한다.
yq -o=json '.' "$ROOT/ansible/roles/ai_agent/tasks/main.yml" >"$TMP/role-tasks.json"
python3 - "$TMP" "$FIXTURE" <<'PY'
import json
import sys
from pathlib import Path

tmp, fixture = map(Path, sys.argv[1:])
tasks = json.loads((tmp / "role-tasks.json").read_text())
backup_name = "Dotfiles 로컬 룰셋 목적지 충돌 백업"
link_name = "Dotfiles 로컬 룰셋 심볼릭 링크 생성"
backups = [(i, task) for i, task in enumerate(tasks) if task.get("name") == backup_name]
links = [(i, task) for i, task in enumerate(tasks) if task.get("name") == link_name]
assert len(backups) == len(links) == 1, "루트 룰셋 백업·링크 태스크가 각각 하나여야 합니다."
assert backups[0][0] < links[0][0], "루트 룰셋 링크 이전에 백업해야 합니다."
argv = backups[0][1]["ansible.builtin.command"]["argv"]
assert argv[2] == "--link-pairs", "외부 symlink도 보존하는 소유권 인식 백업이 필요합니다."
assert len(argv) == 7, "AGENTS.md 및 CLAUDE.md 두 쌍을 전달해야 합니다."
playbook = [{
    "name": "격리된 dotfiles 루트 룰셋 링크 테스트",
    "hosts": "localhost",
    "gather_facts": False,
    "vars": {"role_path": str(fixture / "ansible/roles/ai_agent")},
    "tasks": [backups[0][1], links[0][1]],
}]
(tmp / "playbook.json").write_text(json.dumps(playbook))
PY

ansible-playbook -i localhost, -c local "$TMP/playbook.json" >"$TMP/first.log" 2>&1 || {
  cat "$TMP/first.log"
  exit 1
}

python3 - "$FIXTURE" "$TMP" <<'PY'
import sys
from pathlib import Path

fixture, tmp = map(Path, sys.argv[1:])
source = fixture / "contexts/dotfiles/SKILL.md"
for name in ("AGENTS.md", "CLAUDE.md"):
    target = fixture / name
    assert target.is_symlink() and target.resolve() == source, f"{name}: 관리 링크 설치 실패"
    backups = list(fixture.glob(name + ".backup.*"))
    assert len(backups) == 1, f"{name}: 백업이 정확히 하나 필요합니다"
    if name == "AGENTS.md":
        assert backups[0].read_text() == "keep user AGENTS\n"
    else:
        assert backups[0].is_symlink()
        assert backups[0].readlink() == tmp / "claude-user.md"
print("PASS: 기존 사용자 파일·외부 링크 백업 후 루트 룰셋 설치")
PY

ansible-playbook -i localhost, -c local "$TMP/playbook.json" >"$TMP/second.log" 2>&1 || {
  cat "$TMP/second.log"
  exit 1
}
grep -Eq 'changed=0([[:space:]]|$)' "$TMP/second.log" || {
  cat "$TMP/second.log"
  echo "FAIL: 루트 룰셋 재실행 후 changed=0이어야 합니다." >&2
  exit 1
}
echo "PASS: 관리 링크 재실행 멱등성 및 기존 백업 보존"
