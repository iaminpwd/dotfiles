#!/usr/bin/env bash
# 실제 Ansible 태스크를 임시 홈에서 실행해 일괄 백업의 대상 필터와 인자 보존을 검증한다.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ANSIBLE_HOME="$TMP/ansible"
yq -o=json '.' "$ROOT/ansible/roles/ai_agent/tasks/main.yml" >"$TMP/tasks.json"
python3 - "$ROOT" "$TMP" <<'PY'
import json
import sys
from pathlib import Path

root, tmp = map(Path, sys.argv[1:])
tasks = json.loads((tmp / "tasks.json").read_text())
backups = [t for t in tasks if "safe-link-backup.sh" in
           t.get("ansible.builtin.command", {}).get("argv", "")]
assert len(backups) == 1, "global script 평탄화를 제거한 뒤에는 스킬 에셋 백업만 남아야 한다"
home = tmp / "home space $HOME"
domain = "demo space\n$HOME"
assets = [
    {"item": [{"path": "/source/contexts/" + domain}, "SKILL.md"], "stat": {"exists": True}},
    {"item": [{"path": "/source/contexts/" + domain}, "scripts"], "stat": {"exists": False}},
    {"item": [{"path": "/source/contexts/dotfiles"}, "SKILL.md"], "stat": {"exists": True}},
]
expected = []
excluded = []
foreign_links = []
owned_links = []
source = "/source/contexts/" + domain + "/SKILL.md"
for index, client in enumerate((".gemini/config", ".claude", ".agents")):
    path = home / client / "skills" / domain / "SKILL.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    if index == 0:
        path.write_text("preserve\n")
        expected.append(path)
    elif index == 1:
        path.symlink_to("/private/user-defined/CLAUDE.md")
        foreign_links.append(path)
    else:
        path.symlink_to(source)
        owned_links.append(path)
    excluded.extend([home / client / "skills" / domain / "scripts",
                     home / client / "skills/dotfiles/SKILL.md"])
for path in excluded:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("preserve\n")
(tmp / "paths.json").write_text(json.dumps([list(map(str, expected)),
                                            list(map(str, excluded)),
                                            list(map(str, foreign_links)),
                                            list(map(str, owned_links)),
                                            source]))
variables = {"ansible_env": {"HOME": str(home)},
             "role_path": str(root / "ansible/roles/ai_agent"),
             "ai_agent_skill_assets_stat": {"results": assets}}
# 같은 태스크를 두 번 실행하고 빈 목록도 실행해 멱등성과 무동작을 확인한다.
empty = {**variables, "ai_agent_skill_assets_stat": {"results": []}}
plays = [{"name": "일괄 백업 회귀 검증", "hosts": "localhost", "gather_facts": False,
          "vars": values, "tasks": selected}
         for values, selected in ((variables, backups + backups), (empty, backups))]
(tmp / "playbook.json").write_text(json.dumps(plays))
PY
if ! ansible-playbook -i localhost, -c local "$TMP/playbook.json" >"$TMP/output" 2>&1; then
  cat "$TMP/output"
  exit 1
fi
python3 - "$TMP" <<'PY'
import json
import sys
from pathlib import Path

expected, excluded, foreign_links, owned_links, source = json.loads(
    (Path(sys.argv[1]) / "paths.json").read_text())
for name in expected:
    path = Path(name)
    backups = list(path.parent.glob(path.name + ".backup.*"))
    assert not path.exists() and len(backups) == 1, name
    assert backups[0].read_text() == "preserve\n", name
for name in foreign_links:
    path = Path(name)
    backups = list(path.parent.glob(path.name + ".backup.*"))
    assert not path.is_symlink() and len(backups) == 1, name
    assert backups[0].is_symlink(), name
    assert backups[0].readlink() == Path("/private/user-defined/CLAUDE.md"), name
for name in owned_links:
    path = Path(name)
    assert path.is_symlink() and path.readlink() == Path(source), name
    assert not list(path.parent.glob(path.name + ".backup.*")), name
for name in excluded:
    path = Path(name)
    assert path.read_text() == "preserve\n", name
    assert not list(path.parent.glob(path.name + ".backup.*")), name
print("PASS: 실제 Ansible 스킬 백업의 대상 필터·특수 경로·재실행·빈 목록")
PY
