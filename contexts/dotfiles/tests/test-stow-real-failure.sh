#!/usr/bin/env bash
# Real GNU Stow syscall failure regression, in a disposable HOME only.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
if ! command -v stow >/dev/null 2>&1 || ! command -v ansible-playbook >/dev/null 2>&1; then
  if [ "${STOW_REQUIRE_REAL:-0}" = 1 ]; then
    echo 'FAIL: GNU Stow and Ansible are required in bootstrap smoke' >&2
    exit 1
  fi
  echo '[WARNING] SKIP: GNU Stow / Ansible not available'
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ANSIBLE_HOME="$TMP/ansible"
export ANSIBLE_LOCAL_TEMP="$TMP/local"
export ANSIBLE_REMOTE_TEMP="$TMP/remote"
mkdir -p "$ANSIBLE_HOME" "$ANSIBLE_LOCAL_TEMP" "$ANSIBLE_REMOTE_TEMP" "$TMP/faultlib"

# Intercept a real Perl symlink syscall rather than replacing GNU Stow.
# The second creation returns EIO; the first creation remains applied.
cat >"$TMP/faultlib/StowFault.pm" <<'PERL'
package StowFault;
use strict;
use warnings;
BEGIN {
  *CORE::GLOBAL::symlink = sub {
    ++$StowFault::calls;
    if ($ENV{STOW_FAULT_AT} && $StowFault::calls == $ENV{STOW_FAULT_AT}) {
      $! = 5; # EIO
      return 0;
    }
    return CORE::symlink($_[0], $_[1]);
  };
}
1;
PERL

python3 - "$ROOT" "$TMP" "$(command -v stow)" <<'PY'
from pathlib import Path
import json
import shutil
import sys

root, tmp = map(Path, sys.argv[1:3])
real_stow = sys.argv[3]
repo = tmp / "repo"
role = repo / "ansible/roles/stow/tasks"
source = repo / "stow/demo"
home = tmp / "home"
fakebin = tmp / "bin"
for directory in (role, source, home, fakebin, repo / "bin/utils"):
    directory.mkdir(parents=True, exist_ok=True)
(source / ".first").write_text("managed first\n")
(source / ".second").write_text("managed second\n")
(home / ".first").write_text("original user first\n")
shutil.copy2(root / "ansible/roles/stow/tasks/package.yml", role / "package.yml")
shutil.copy2(root / "bin/utils/stow-backup.sh",
             repo / "bin/utils/stow-backup.sh")
shutil.copy2(root / "bin/utils/stow-filter-inventory.pl",
             repo / "bin/utils/stow-filter-inventory.pl")
(role / "main.yml").write_text("""---
- name: Run actual package tasks
  ansible.builtin.include_tasks: package.yml
  loop: "{{ stow_dirs.files }}"
  loop_control:
    loop_var: stow_package
""")
(fakebin / "stow").write_text("""#!/usr/bin/env bash
set -euo pipefail
printf 'called\\n' >>"$STOW_CALL_LOG"
exec "$STOW_REAL_BIN" "$@"
""")
(fakebin / "stow").chmod(0o755)
play = [{
    "hosts": "localhost", "connection": "local", "gather_facts": False,
    "environment": {
        "HOME": str(home),
        "PATH": str(fakebin) + ":{{ lookup('env', 'PATH') }}",
        "PERL5LIB": str(tmp / "faultlib"),
        "PERL5OPT": "-MStowFault",
        "STOW_FAULT_AT": "{{ lookup('env', 'STOW_FAULT_AT') }}",
        "STOW_CALL_LOG": str(tmp / "calls"),
        "STOW_REAL_BIN": real_stow,
    },
    "vars": {
        "ansible_env": {"HOME": str(home)},
        "stow_dirs": {"files": [{"path": str(source)}]},
    },
    "roles": ["stow"],
}]
(tmp / "play.yml").write_text(json.dumps(play))
PY

HOME_DIR="$TMP/home"
ROLES="$TMP/repo/ansible/roles"
status=0
STOW_FAULT_AT=2 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/fail.out" 2>&1 || status=$?
BACKUPS=("$HOME_DIR"/.first.backup.*)
links=0
for leaf in .first .second; do
  if [ -L "$HOME_DIR/$leaf" ]; then
    links=$((links + 1))
  fi
done
if [ "$status" -eq 0 ] ||
  ! grep -q 'Could not create symlink' "$TMP/fail.out" ||
  ! grep -Eq 'failed=1([^0-9]|$)' "$TMP/fail.out" ||
  [ "$links" -ne 1 ] ||
  [ ! -f "${BACKUPS[0]}" ] ||
  ! grep -qx 'original user first' "${BACKUPS[0]}" ||
  [ "$(wc -l <"$TMP/calls")" -ne 1 ]; then
  cat "$TMP/fail.out"
  echo 'FAIL: actual Stow EIO did not leave one link and preserve the backup'
  exit 1
fi

# Read-only check after the partial failure.
before=$(find "$HOME_DIR" -maxdepth 1 -type l -print | sort)
status=0
STOW_FAULT_AT=0 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$TMP/play.yml" --check >"$TMP/check.out" 2>&1 || status=$?
after=$(find "$HOME_DIR" -maxdepth 1 -type l -print | sort)
if [ "$status" -ne 0 ] ||
  [ "$before" != "$after" ] ||
  [ "$(wc -l <"$TMP/calls")" -ne 1 ] ||
  ! grep -q '재링크 예정' "$TMP/check.out" ||
  ! grep -qx 'original user first' "${BACKUPS[0]}"; then
  cat "$TMP/check.out"
  echo 'FAIL: dry-run changed links or missed partial drift'
  exit 1
fi

# Fault-free retry must converge with the original user backup intact.
status=0
STOW_FAULT_AT=0 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/retry.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  [ ! -L "$HOME_DIR/.first" ] ||
  [ ! -L "$HOME_DIR/.second" ] ||
  ! grep -qx 'managed first' "$HOME_DIR/.first" ||
  ! grep -qx 'managed second' "$HOME_DIR/.second" ||
  ! grep -qx 'original user first' "${BACKUPS[0]}" ||
  [ "$(wc -l <"$TMP/calls")" -ne 2 ] ||
  ! grep -Eq 'changed=1([^0-9]|$)' "$TMP/retry.out"; then
  cat "$TMP/retry.out"
  echo 'FAIL: retry lost a backup or failed to converge'
  exit 1
fi

status=0
STOW_FAULT_AT=0 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/clean.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  [ "$(wc -l <"$TMP/calls")" -ne 2 ] ||
  ! grep -Eq 'changed=0([^0-9]|$)' "$TMP/clean.out" ||
  ! grep -qx 'original user first' "${BACKUPS[0]}"; then
  cat "$TMP/clean.out"
  echo 'FAIL: clean package was unnecessarily redeployed'
  exit 1
fi
echo 'PASS: real GNU Stow EIO, safe backup, dry-run, retry, and idempotency'
