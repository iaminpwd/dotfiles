#!/usr/bin/env bash
# Regression: partial secure-link EIO, backup preservation, dry-run, retry.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
if ! command -v stow >/dev/null 2>&1 || ! command -v ansible-playbook >/dev/null 2>&1; then
  if [ "${STOW_REQUIRE_REAL:-0}" = 1 ]; then
    echo 'FAIL: Stow and Ansible required' >&2
    exit 1
  fi
  echo '[WARNING] SKIP: GNU Stow / Ansible not available'
  exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ANSIBLE_HOME="$TMP/ansible" ANSIBLE_LOCAL_TEMP="$TMP/local" ANSIBLE_REMOTE_TEMP="$TMP/remote"
mkdir -p "$ANSIBLE_HOME" "$ANSIBLE_LOCAL_TEMP" "$ANSIBLE_REMOTE_TEMP"

python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import json
import shutil
import sys

root, tmp = map(Path, sys.argv[1:])
repo = tmp / "repo"
role = repo / "ansible/roles/stow/tasks"
source = repo / "stow/demo"
home = tmp / "home"
for directory in (role, source, home, repo / "bin/utils"):
    directory.mkdir(parents=True, exist_ok=True)
(source / ".first").write_text("managed first\n")
(source / ".second").write_text("managed second\n")
(home / ".first").write_text("original user first\n")
for path in ("ansible/roles/stow/tasks/package.yml",
             "bin/utils/stow-backup.sh",
             "bin/utils/stow-filter-inventory.pl",
             "bin/utils/stow-safe-backup.py",
             "bin/utils/stow-safe-install.py"):
    shutil.copy2(root / path, repo / path)
(role / "main.yml").write_text("""---
- name: Run actual package tasks
  ansible.builtin.include_tasks: package.yml
  loop: "{{ stow_dirs.files }}"
  loop_control:
    loop_var: stow_package
""")
play = [{"hosts": "localhost", "connection": "local", "gather_facts": False,
         "environment": {"HOME": str(home)},
         "vars": {"ansible_env": {"HOME": str(home)},
                  "stow_dirs": {"files": [{"path": str(source)}]}},
         "roles": ["stow"]}]
(tmp / "play.yml").write_text(json.dumps(play))
PY

HOME_DIR="$TMP/home"
ROLES="$TMP/repo/ansible/roles"
HOME="$HOME_DIR" bash "$TMP/repo/bin/utils/stow-backup.sh" \
  demo "$TMP/repo/stow" "$HOME_DIR"
BACKUPS=("$HOME_DIR"/.first.backup.*)
if [ ! -f "${BACKUPS[0]}" ] ||
  ! grep -qx 'original user first' "${BACKUPS[0]}" ||
  [ -e "$HOME_DIR/.first" ]; then
  echo 'FAIL: user backup missing before injected failure'
  exit 1
fi

STOW_TEST_HELPER="$TMP/repo/bin/utils/stow-safe-install.py" \
  STOW_TEST_REPO="$TMP/repo" STOW_TEST_HOME="$HOME_DIR" python3 - <<'PY'
import errno
import importlib.util
import os
from pathlib import Path

spec = importlib.util.spec_from_file_location("safe_installer", os.environ["STOW_TEST_HELPER"])
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
real = os.symlink
count = [0]

def inject(target, name, *args, **kwargs):
    if kwargs.get("dir_fd") is not None:
        count[0] += 1
        if count[0] == 2:
            raise OSError(errno.EIO, "injected second symlink EIO")
    return real(target, name, *args, **kwargs)

os.symlink = inject
try:
    try:
        helper.install(str(Path(os.environ["STOW_TEST_REPO"]) / "stow"),
                       "demo", os.environ["STOW_TEST_HOME"])
    except OSError as exc:
        assert exc.errno == errno.EIO
    else:
        raise AssertionError("injected second symlink EIO did not abort")
finally:
    os.symlink = real
assert count[0] == 2
PY

links=0
for leaf in .first .second; do
  [ ! -L "$HOME_DIR/$leaf" ] || links=$((links + 1))
done
if [ "$links" -ne 1 ] ||
  ! grep -qx 'original user first' "${BACKUPS[0]}"; then
  echo 'FAIL: partial secure install lost the source backup'
  exit 1
fi

before=$(find "$HOME_DIR" -maxdepth 1 -type l -print | sort)
status=0
ANSIBLE_ROLES_PATH="$ROLES" ansible-playbook -i localhost, "$TMP/play.yml" --check \
  >"$TMP/check.out" 2>&1 || status=$?
after=$(find "$HOME_DIR" -maxdepth 1 -type l -print | sort)
if [ "$status" -ne 0 ] || [ "$before" != "$after" ] ||
  ! grep -q '재링크 예정' "$TMP/check.out" ||
  ! grep -qx 'original user first' "${BACKUPS[0]}"; then
  cat "$TMP/check.out"
  echo 'FAIL: dry-run mutated the partial install'
  exit 1
fi

status=0
ANSIBLE_ROLES_PATH="$ROLES" ansible-playbook -i localhost, "$TMP/play.yml" \
  >"$TMP/retry.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  [ ! -L "$HOME_DIR/.first" ] || [ ! -L "$HOME_DIR/.second" ] ||
  ! grep -qx 'managed first' "$HOME_DIR/.first" ||
  ! grep -qx 'managed second' "$HOME_DIR/.second" ||
  ! grep -qx 'original user first' "${BACKUPS[0]}" ||
  ! grep -Eq 'changed=1([^0-9]|$)' "$TMP/retry.out"; then
  cat "$TMP/retry.out"
  echo 'FAIL: retry lost the backup or did not converge'
  exit 1
fi

status=0
ANSIBLE_ROLES_PATH="$ROLES" ansible-playbook -i localhost, "$TMP/play.yml" \
  >"$TMP/clean.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  ! grep -Eq 'changed=0([^0-9]|$)' "$TMP/clean.out" ||
  ! grep -qx 'original user first' "${BACKUPS[0]}"; then
  cat "$TMP/clean.out"
  echo 'FAIL: clean setup broke idempotency or lost backup'
  exit 1
fi
echo 'PASS: safe installer EIO preserves data, dry-run, retry, and idempotency'
