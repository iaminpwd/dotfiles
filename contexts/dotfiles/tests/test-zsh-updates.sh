#!/usr/bin/env bash
# 실제 git 태스크로 신규 설치 → 버전 갱신 → 동일 버전 재실행을 검증한다.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ANSIBLE_HOME="$TMP/ansible" ANSIBLE_LOCAL_TEMP="$TMP/local" ANSIBLE_REMOTE_TEMP="$TMP/remote"
mkdir -p "$TMP/origin" "$TMP/home"
git -C "$TMP/origin" init -q
git -C "$TMP/origin" config user.name Test
git -C "$TMP/origin" config user.email test@example.com
for revision in v1 v2; do
  printf '%s\n' "$revision" >"$TMP/origin/revision.txt"
  git -C "$TMP/origin" add revision.txt
  git -C "$TMP/origin" -c core.hooksPath=/dev/null commit -qm "chore: $revision"
  git -C "$TMP/origin" tag "$revision"
done
python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import json
import re
import sys
root, tmp = map(Path, sys.argv[1:])
source = (root / 'ansible/roles/zsh/tasks/main.yml').read_text()
tasks = source.split('- name: 현재 설치된 zsh 경로 확인')[0]
tasks = re.sub(r"repo: '[^']+'", f"repo: 'file://{tmp}/origin'", tasks)
tasks = re.sub(r'    version: .+', '    version: "{{ desired_revision }}"', tasks)
(tmp / 'tasks.yml').write_text(tasks)
(tmp / 'play.yml').write_text(json.dumps([{
    'name': 'Zsh 업데이트 회귀', 'hosts': 'localhost', 'connection': 'local',
    'gather_facts': False, 'vars': {'ansible_env': {'HOME': str(tmp / 'home')}},
    'tasks': [{'name': '실제 Git 태스크', 'ansible.builtin.import_tasks': str(tmp / 'tasks.yml')}],
}]))
PY
for revision in v1 v2 v2; do
  ansible-playbook -i localhost, "$TMP/play.yml" -e "desired_revision=$revision" >"$TMP/out" 2>&1 || {
    cat "$TMP/out"
    exit 1
  }
  for path in .oh-my-zsh .oh-my-zsh/custom/plugins/zsh-autosuggestions .oh-my-zsh/custom/plugins/zsh-syntax-highlighting; do
    [ "$(cat "$TMP/home/$path/revision.txt")" = "$revision" ]
  done
done
grep -q 'changed=0' "$TMP/out"
echo 'PASS: Zsh 본체·플러그인 갱신과 동일 버전 멱등성'
