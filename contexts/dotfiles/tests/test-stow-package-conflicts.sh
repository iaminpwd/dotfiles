#!/usr/bin/env bash
# Different Stow packages must not manage the same HOME entry. Otherwise each
# rerun replaces the other package link and creates additional user backups.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
if ! command -v stow >/dev/null 2>&1; then
  echo '[WARNING] SKIP: GNU Stow unavailable'
  exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/stow/a" "$TMP/stow/b" "$TMP/home"
printf 'A\n' >"$TMP/stow/a/.shared"
printf 'B\n' >"$TMP/stow/b/.shared"
printf 'user data\n' >"$TMP/home/.shared"

INSTALL="$ROOT/bin/utils/stow-safe-install.py"
code=0
out=$(python3 "$INSTALL" --check-packages "$TMP/stow" "$TMP/home" a b 2>&1) || code=$?
if [ "$code" -eq 0 ] || ! grep -qF 'conflict' <<<"$out" ||
  ! grep -qx 'user data' "$TMP/home/.shared"; then
  echo "FAIL: overlapping packages accepted or user data lost: rc=$code $out" >&2
  exit 1
fi
echo 'PASS: 두 패키지의 동일 리프 대상 충돌을 설치 전에 차단'

rm "$TMP/stow/b/.shared"
mkdir -p "$TMP/stow/b/.shared"
printf 'nested\n' >"$TMP/stow/b/.shared/child"
code=0
out=$(python3 "$INSTALL" --check-packages "$TMP/stow" "$TMP/home" a b 2>&1) || code=$?
if [ "$code" -eq 0 ] || ! grep -qF 'conflict' <<<"$out"; then
  echo "FAIL: file/parent collision accepted: rc=$code $out" >&2
  exit 1
fi
echo 'PASS: 한 패키지의 리프와 다른 패키지의 디렉터리 충돌 차단'

rm -rf "$TMP/stow/b/.shared"
printf 'B\n' >"$TMP/stow/b/.other"
python3 "$INSTALL" --check-packages "$TMP/stow" "$TMP/home" a b
grep -qx 'user data' "$TMP/home/.shared"
echo 'PASS: 비중복 패키지는 백업·HOME 변경 없이 통과'

# Even a package with an ignored file must not create a false collision.
printf 'B\n' >"$TMP/stow/b/.shared"
printf '^\\.shared$\n' >"$TMP/stow/b/.stow-local-ignore"
python3 "$INSTALL" --check-packages "$TMP/stow" "$TMP/home" a b
echo 'PASS: GNU Stow ignore 규칙을 따른 목적지 집합 비교'

# Inspect and execute the *real* Ansible preflight task, including --check
# mode. A helper that works alone is insufficient if the role forgets to call
# it or runs it after the package loop.
if command -v ansible-playbook >/dev/null 2>&1 && command -v yq >/dev/null 2>&1; then
  rm "$TMP/stow/b/.stow-local-ignore"
  mkdir -p "$TMP/ansible/roles/stow" "$TMP/bin/utils"
  cp "$ROOT/bin/utils/stow-safe-install.py" "$ROOT/bin/utils/stow-filter-inventory.pl" "$TMP/bin/utils/"
  yq -o=json '.' "$ROOT/ansible/roles/stow/tasks/main.yml" >"$TMP/role.json"
  python3 - "$TMP" <<'PY'
import json
import sys
from pathlib import Path

tmp = Path(sys.argv[1])
tasks = json.loads((tmp / "role.json").read_text())
preflight = [i for i, t in enumerate(tasks)
             if t.get("name") == "Stow 패키지 간 관리 경로 충돌 검사 (읽기 전용)"]
loop = [i for i, t in enumerate(tasks)
        if t.get("name") == "Stow 패키지별 백업·드리프트 판정·적용"]
assert len(preflight) == len(loop) == 1 and preflight[0] < loop[0], (
    "Ansible preflight must run once before package mutations")
play = [{
    "hosts": "localhost", "gather_facts": False,
    "vars": {
        "role_path": str(tmp / "ansible/roles/stow"),
        "ansible_env": {"HOME": str(tmp / "home")},
        "stow_dirs": {"files": [
            {"path": str(tmp / "stow/a")},
            {"path": str(tmp / "stow/b")},
        ]},
    },
    "tasks": [tasks[preflight[0]]],
}]
(tmp / "play.json").write_text(json.dumps(play))
PY
  export ANSIBLE_HOME="$TMP/ansible-home"
  code=0
  ansible-playbook -i localhost, -c local --check "$TMP/play.json" >"$TMP/ansible-fail.log" 2>&1 || code=$?
  if [ "$code" -eq 0 ] || ! grep -q 'Stow package conflict' "$TMP/ansible-fail.log" ||
    ! grep -qx 'user data' "$TMP/home/.shared"; then
    cat "$TMP/ansible-fail.log"
    echo 'FAIL: Ansible check mode accepted overlapping packages' >&2
    exit 1
  fi
  rm "$TMP/stow/b/.shared"
  ansible-playbook -i localhost, -c local --check "$TMP/play.json" >"$TMP/ansible-ok.log" 2>&1 || {
    cat "$TMP/ansible-ok.log"
    exit 1
  }
  grep -Eq 'changed=0([[:space:]]|$)' "$TMP/ansible-ok.log"
  echo 'PASS: 실제 Ansible 패키지 루프 앞 preflight 및 --check 멱등성'
fi
