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
assert len(backups) == 2, "스크립트·스킬 백업은 각각 한 태스크여야 한다"
home = tmp / "home space $HOME"
domain = "demo space\n$HOME"
scripts = [
    {"path": "/source/bin/tool name.sh", "mode": "0755"},
    {"path": "/source/bin/readonly.sh", "mode": "0644"},
    {"path": "/source/contexts/.shared/scripts/hidden.sh", "mode": "0755"},
    {"path": "/source/contexts/demo/tests/test.sh", "mode": "0755"},
]
assets = [
    {"item": [{"path": "/source/contexts/" + domain}, "SKILL.md"], "stat": {"exists": True}},
    {"item": [{"path": "/source/contexts/" + domain}, "scripts"], "stat": {"exists": False}},
    {"item": [{"path": "/source/contexts/dotfiles"}, "SKILL.md"], "stat": {"exists": True}},
]
expected = [home / ".local/bin/tool name.sh"]
excluded = [home / ".local/bin" / name for name in ("readonly.sh", "hidden.sh", "test.sh")]
for client in (".gemini/config", ".claude", ".agents"):
    expected.append(home / client / "skills" / domain / "SKILL.md")
    excluded.extend([home / client / "skills" / domain / "scripts",
                     home / client / "skills/dotfiles/SKILL.md"])
for path in expected + excluded:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("preserve\n")
(tmp / "paths.json").write_text(json.dumps([list(map(str, expected)), list(map(str, excluded))]))
variables = {"ansible_env": {"HOME": str(home)},
             "role_path": str(root / "ansible/roles/ai_agent"),
             "ai_agent_scripts_find": {"files": scripts},
             "ai_agent_skill_assets_stat": {"results": assets}}
# 같은 태스크를 두 번 실행하고 빈 목록도 실행해 멱등성과 무동작을 확인한다.
empty = {**variables, "ai_agent_scripts_find": {"files": []},
         "ai_agent_skill_assets_stat": {"results": []}}
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

expected, excluded = json.loads((Path(sys.argv[1]) / "paths.json").read_text())
for name in expected:
    path = Path(name)
    backups = list(path.parent.glob(path.name + ".backup.*"))
    assert not path.exists() and len(backups) == 1, name
    assert backups[0].read_text() == "preserve\n", name
for name in excluded:
    path = Path(name)
    assert path.read_text() == "preserve\n", name
    assert not list(path.parent.glob(path.name + ".backup.*")), name
print("PASS: 실제 Ansible 일괄 백업의 대상 필터·특수 경로·재실행·빈 목록")
PY
