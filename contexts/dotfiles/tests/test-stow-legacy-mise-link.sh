#!/usr/bin/env bash
# stow role은 이 저장소가 만든 구버전 ~/.mise.toml 링크만 정리해야 한다.
# 사용자가 별도로 만든 ~/.mise.toml symlink는 사용자 설정이므로 보존한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo '[WARNING] SKIP: ansible-playbook 필요 (stow legacy mise link 회귀)'
  exit 0
fi

export ANSIBLE_HOME="$TMP/ansible"
export ANSIBLE_LOCAL_TEMP="$TMP/local"
export ANSIBLE_REMOTE_TEMP="$TMP/remote"

mkdir -p "$TMP/repo/ansible/roles/stow/tasks" "$TMP/repo/mise" "$TMP/private" "$TMP/home-user" "$TMP/home-legacy"
printf 'legacy=true\n' >"$TMP/repo/mise/.mise.toml"
printf 'user=true\n' >"$TMP/private/mise.toml"

python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import json
import sys

root, tmp = map(Path, sys.argv[1:])
source = (root / "ansible/roles/stow/tasks/main.yml").read_text()
marker = "- name: Dotfiles 하위의 stow 대상 디렉토리 목록 스캔"
subset = source[: source.index(marker)].rstrip() + "\n"
(tmp / "repo/ansible/roles/stow/tasks/main.yml").write_text(subset)
(tmp / "play.yml").write_text(json.dumps([{
    "name": "Stow legacy mise symlink regression",
    "hosts": "localhost",
    "connection": "local",
    "gather_facts": False,
    "vars": {
        "ansible_env": {
            "HOME": "{{ lookup('env', 'STOW_TEST_HOME') }}"
        }
    },
    "roles": ["stow"],
}]))
PY

# 사용자 소유의 별도 mise 설정 링크는 절대 삭제하면 안 된다.
ln -s "../private/mise.toml" "$TMP/home-user/.mise.toml"
STOW_TEST_HOME="$TMP/home-user" ANSIBLE_ROLES_PATH="$TMP/repo/ansible/roles" \
  ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/user.out" 2>&1 || {
    cat "$TMP/user.out"
    exit 1
  }

if [ ! -L "$TMP/home-user/.mise.toml" ] ||
  [ "$(readlink "$TMP/home-user/.mise.toml")" != "../private/mise.toml" ]; then
  cat "$TMP/user.out"
  echo 'FAIL: unrelated user ~/.mise.toml symlink was removed'
  exit 1
fi

# 반대로 이 저장소의 옛 mise/.mise.toml을 가리키는 링크는 업그레이드 잔재라 정리해야 한다.
ln -s "../repo/mise/.mise.toml" "$TMP/home-legacy/.mise.toml"
STOW_TEST_HOME="$TMP/home-legacy" ANSIBLE_ROLES_PATH="$TMP/repo/ansible/roles" \
  ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/legacy.out" 2>&1 || {
    cat "$TMP/legacy.out"
    exit 1
  }

if [ -e "$TMP/home-legacy/.mise.toml" ] || [ -L "$TMP/home-legacy/.mise.toml" ]; then
  cat "$TMP/legacy.out"
  echo 'FAIL: repository-owned legacy ~/.mise.toml symlink was not removed'
  exit 1
fi

echo 'PASS: stow role removes only repository-owned legacy ~/.mise.toml links'
