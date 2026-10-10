#!/usr/bin/env bash
# Backup must leave GNU Stow-ignored user files in place, without guesswork.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
BACKUP="$ROOT/bin/utils/stow-backup.sh"
if ! command -v stow >/dev/null 2>&1; then
  if [ "${STOW_REQUIRE_REAL:-0}" = 1 ]; then
    echo 'FAIL: GNU Stow is required for ignore parity regression' >&2
    exit 1
  fi
  echo '[WARNING] SKIP: GNU Stow is not installed'
  exit 0
fi
# A HOME-scoped fixture must not make mise's python3 shim reinstall Python
# into each disposable HOME. Use the OS interpreter for the backup helper
# when it is already available; leave other executable resolution unchanged.
PYTHON_SHIM_DIR=""
if [ -x /usr/bin/python3 ]; then
  PYTHON_SHIM_DIR=$(mktemp -d)
  ln -s /usr/bin/python3 "$PYTHON_SHIM_DIR/python3"
  export PATH="$PYTHON_SHIM_DIR:$PATH"
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP" "${PYTHON_SHIM_DIR:-}"' EXIT

# Global ignore: user content excluded by Stow must never be backed up.
CASE="$TMP/global"
mkdir -p "$CASE/stow/demo" "$CASE/home"
printf 'managed skip\n' >"$CASE/stow/demo/.skip"
printf 'managed install\n' >"$CASE/stow/demo/.install"
printf 'user skip\n' >"$CASE/home/.skip"
printf 'user install\n' >"$CASE/home/.install"
printf '^\\.skip$\n' >"$CASE/home/.stow-global-ignore"
HOME="$CASE/home" bash "$BACKUP" demo "$CASE/stow" "$CASE/home"
BACKUPS=("$CASE/home"/.install.backup.*)
SKIP_BACKUPS=("$CASE/home"/.skip.backup.*)
if ! grep -qx 'user skip' "$CASE/home/.skip" ||
  [ -e "${SKIP_BACKUPS[0]}" ] ||
  [ ! -f "${BACKUPS[0]}" ] ||
  ! grep -qx 'user install' "${BACKUPS[0]}" ||
  [ -e "$CASE/home/.install" ]; then
  echo 'FAIL: global Stow ignore moved the user-owned ignored file'
  exit 1
fi
(
  cd "$CASE/stow"
  HOME="$CASE/home" stow -R --no-folding -t "$CASE/home" demo
)
if [ ! -L "$CASE/home/.install" ] ||
  ! grep -qx 'managed install' "$CASE/home/.install" ||
  ! grep -qx 'user skip' "$CASE/home/.skip" ||
  ! grep -qx 'user install' "${BACKUPS[0]}"; then
  echo 'FAIL: real GNU Stow and backup disagree on global ignore'
  exit 1
fi

# A local ignore file overrides the global ignore rules for this package.
# Also exercise ignored directories whose HOME path is an existing user file.
CASE="$TMP/local"
mkdir -p "$CASE/stow/demo/.excluded" "$CASE/home"
printf 'managed skip\n' >"$CASE/stow/demo/.skip"
printf 'managed nested\n' >"$CASE/stow/demo/.excluded/private"
printf 'managed install\n' >"$CASE/stow/demo/.install"
printf 'user skip\n' >"$CASE/home/.skip"
printf 'user excluded\n' >"$CASE/home/.excluded"
printf 'user install\n' >"$CASE/home/.install"
printf '^\\.skip$\n^\\.excluded$\n' >"$CASE/stow/demo/.stow-local-ignore"
printf '^\\.something-else$\n' >"$CASE/home/.stow-global-ignore"
HOME="$CASE/home" bash "$BACKUP" demo "$CASE/stow" "$CASE/home"
BACKUPS=("$CASE/home"/.install.backup.*)
SKIP_BACKUPS=("$CASE/home"/.skip.backup.*)
EXCLUDED_BACKUPS=("$CASE/home"/.excluded.backup.*)
if ! grep -qx 'user skip' "$CASE/home/.skip" ||
  ! grep -qx 'user excluded' "$CASE/home/.excluded" ||
  [ -e "${SKIP_BACKUPS[0]}" ] ||
  [ -e "${EXCLUDED_BACKUPS[0]}" ] ||
  ! grep -qx 'user install' "${BACKUPS[0]}"; then
  echo 'FAIL: local ignore or ignored directory altered user files'
  exit 1
fi
(
  cd "$CASE/stow"
  HOME="$CASE/home" stow -R --no-folding -t "$CASE/home" demo
)
if [ ! -L "$CASE/home/.install" ] ||
  ! grep -qx 'user skip' "$CASE/home/.skip" ||
  ! grep -qx 'user excluded' "$CASE/home/.excluded" ||
  ! grep -qx 'user install' "${BACKUPS[0]}"; then
  echo 'FAIL: real Stow and backup disagree on local ignore'
  exit 1
fi

# Invalid regex: fail closed before moving any user target.
CASE="$TMP/invalid"
mkdir -p "$CASE/stow/demo" "$CASE/home"
printf 'managed install\n' >"$CASE/stow/demo/.install"
printf 'user install\n' >"$CASE/home/.install"
printf '[\n' >"$CASE/home/.stow-global-ignore"
status=0
HOME="$CASE/home" bash "$BACKUP" demo "$CASE/stow" "$CASE/home" >"$CASE/result" 2>&1 || status=$?
BACKUPS=("$CASE/home"/.install.backup.*)
if [ "$status" -eq 0 ] ||
  ! grep -qF '[Hard Block]' "$CASE/result" ||
  ! grep -qx 'user install' "$CASE/home/.install" ||
  [ -e "${BACKUPS[0]}" ]; then
  cat "$CASE/result"
  echo 'FAIL: malformed Stow ignore rules did not block before backup'
  exit 1
fi

# Round 22: installation and drift must use an identical GNU Stow ignore
# inventory. A clean package containing ignored files must stay changed=0.
if command -v ansible-playbook >/dev/null 2>&1; then
  ROLE_IGNORE="$TMP/role-ignore"
  mkdir -p "$ROLE_IGNORE/repo/ansible/roles/stow/tasks" \
    "$ROLE_IGNORE/repo/bin/utils" "$ROLE_IGNORE/repo/stow/demo" "$ROLE_IGNORE/home"
  printf 'managed installed\n' >"$ROLE_IGNORE/repo/stow/demo/.install"
  printf 'managed ignored\n' >"$ROLE_IGNORE/repo/stow/demo/.ignored"
  printf '^\.ignored$\n' >"$ROLE_IGNORE/repo/stow/demo/.stow-local-ignore"
  printf 'original installed\n' >"$ROLE_IGNORE/home/.install"
  printf 'original ignored\n' >"$ROLE_IGNORE/home/.ignored"
  for path in \
    ansible/roles/stow/tasks/package.yml \
    bin/utils/stow-backup.sh \
    bin/utils/stow-filter-inventory.pl \
    bin/utils/stow-safe-backup.py \
    bin/utils/stow-safe-install.py; do
    cp "$ROOT/$path" "$ROLE_IGNORE/repo/$path"
  done
  cat >"$ROLE_IGNORE/repo/ansible/roles/stow/tasks/main.yml" <<'YAML'
---
- name: Apply real Stow package tasks
  ansible.builtin.include_tasks: package.yml
  loop: "{{ stow_dirs.files }}"
  loop_control:
    loop_var: stow_package
YAML
  python3 - "$ROLE_IGNORE" <<'PY'
import json
from pathlib import Path
import sys

case = Path(sys.argv[1])
home = case / "home"
source = case / "repo/stow/demo"
play = [{
    "hosts": "localhost", "connection": "local", "gather_facts": False,
    "environment": {"HOME": str(home)},
    "vars": {
        "ansible_env": {"HOME": str(home)},
        "stow_dirs": {"files": [{"path": str(source)}]},
    },
    "roles": ["stow"],
}]
(case / "play.yml").write_text(json.dumps(play))
PY
  export ANSIBLE_HOME="$ROLE_IGNORE/ansible"
  export ANSIBLE_LOCAL_TEMP="$ROLE_IGNORE/local"
  export ANSIBLE_REMOTE_TEMP="$ROLE_IGNORE/remote"
  mkdir -p "$ANSIBLE_HOME" "$ANSIBLE_LOCAL_TEMP" "$ANSIBLE_REMOTE_TEMP"
  ROLE_PATH="$ROLE_IGNORE/repo/ansible/roles"
  status=0
  ANSIBLE_ROLES_PATH="$ROLE_PATH" ansible-playbook -i localhost, \
    "$ROLE_IGNORE/play.yml" >"$ROLE_IGNORE/initial.out" 2>&1 || status=$?
  INSTALL_BACKUPS=("$ROLE_IGNORE/home"/.install.backup.*)
  IGNORE_BACKUPS=("$ROLE_IGNORE/home"/.ignored.backup.*)
  if [ "$status" -ne 0 ] ||
    ! grep -Eq 'changed=1([^0-9]|$)' "$ROLE_IGNORE/initial.out" ||
    [ ! -L "$ROLE_IGNORE/home/.install" ] ||
    ! grep -qx 'managed installed' "$ROLE_IGNORE/home/.install" ||
    ! grep -qx 'original ignored' "$ROLE_IGNORE/home/.ignored" ||
    [ -e "${IGNORE_BACKUPS[0]}" ] ||
    [ ! -f "${INSTALL_BACKUPS[0]}" ] ||
    ! grep -qx 'original installed' "${INSTALL_BACKUPS[0]}"; then
    cat "$ROLE_IGNORE/initial.out"
    echo 'FAIL: package install did not preserve ignored user data'
    exit 1
  fi
  installed_inode=$(python3 -c 'import os,sys; s=os.lstat(sys.argv[1]); print(s.st_dev,s.st_ino)' "$ROLE_IGNORE/home/.install")
  status=0
  ANSIBLE_ROLES_PATH="$ROLE_PATH" ansible-playbook -i localhost, \
    "$ROLE_IGNORE/play.yml" >"$ROLE_IGNORE/clean.out" 2>&1 || status=$?
  after_inode=$(python3 -c 'import os,sys; s=os.lstat(sys.argv[1]); print(s.st_dev,s.st_ino)' "$ROLE_IGNORE/home/.install")
  if [ "$status" -ne 0 ] ||
    ! grep -Eq 'changed=0([^0-9]|$)' "$ROLE_IGNORE/clean.out" ||
    [ "$installed_inode" != "$after_inode" ] ||
    [ -e "${IGNORE_BACKUPS[0]}" ] ||
    ! grep -qx 'original ignored' "$ROLE_IGNORE/home/.ignored" ||
    ! grep -qx 'original installed' "${INSTALL_BACKUPS[0]}"; then
    cat "$ROLE_IGNORE/clean.out"
    echo 'FAIL: ignored source falsely triggered drift on clean rerun'
    exit 1
  fi
  status=0
  ANSIBLE_ROLES_PATH="$ROLE_PATH" ansible-playbook -i localhost, \
    "$ROLE_IGNORE/play.yml" --check >"$ROLE_IGNORE/dryrun.out" 2>&1 || status=$?
  if [ "$status" -ne 0 ] ||
    ! grep -q '드리프트 없음' "$ROLE_IGNORE/dryrun.out" ||
    [ "$installed_inode" != "$(python3 -c 'import os,sys; s=os.lstat(sys.argv[1]); print(s.st_dev,s.st_ino)' "$ROLE_IGNORE/home/.install")" ] ||
    ! grep -qx 'original ignored' "$ROLE_IGNORE/home/.ignored"; then
    cat "$ROLE_IGNORE/dryrun.out"
    echo 'FAIL: ignored source corrupted dry-run idempotency'
    exit 1
  fi
fi

echo 'PASS: GNU Stow ignore parity (global, local, nested directory, invalid regex, role idempotency)'
