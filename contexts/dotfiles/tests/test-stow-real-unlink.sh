#!/usr/bin/env bash
# Exercise GNU Stow's real unlink syscall failure and later retry in a temp HOME.
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

# A real GNU Stow -R --no-folding can unfold old directory links: first unlink
# succeeds, the second raises EIO. Only intercept matching package-owned links;
# all other file operations use the system implementation.
cat >"$TMP/faultlib/StowUnlinkFault.pm" <<'PERL'
package StowUnlinkFault;
use strict;
use warnings;
BEGIN {
  *CORE::GLOBAL::unlink = sub {
    my $path = $_[0];
    if ($path =~ m{(?:^|/)\.fold-(?:a|b)$}) {
      ++$StowUnlinkFault::calls;
      if (open my $log, '>>', $ENV{STOW_UNLINK_LOG}) {
        print {$log} "$path\n";
        close $log;
      }
      if ($ENV{STOW_UNLINK_FAULT_AT} &&
          $StowUnlinkFault::calls == $ENV{STOW_UNLINK_FAULT_AT}) {
        $! = 5; # EIO
        return 0;
      }
    }
    return CORE::unlink($_[0]);
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
for directory in (role, source / ".fold-a", source / ".fold-b", home,
                  fakebin, repo / "bin/utils"):
    directory.mkdir(parents=True, exist_ok=True)
(source / ".fold-a/managed").write_text("managed a\n")
(source / ".fold-b/managed").write_text("managed b\n")
(source / ".custom").write_text("managed custom\n")
(home / ".custom").write_text("original user custom\n")
# Historical folded Stow links, both pointing to this exact source package.
(home / ".fold-a").symlink_to("../repo/stow/demo/.fold-a")
(home / ".fold-b").symlink_to("../repo/stow/demo/.fold-b")
shutil.copy2(root / "ansible/roles/stow/tasks/package.yml", role / "package.yml")
shutil.copy2(root / "bin/utils/stow-backup.sh",
             repo / "bin/utils/stow-backup.sh")
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
        "PERL5OPT": "-MStowUnlinkFault",
        "STOW_UNLINK_FAULT_AT": "{{ lookup('env', 'STOW_UNLINK_FAULT_AT') }}",
        "STOW_UNLINK_LOG": str(tmp / "unlinks"),
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
# First unlink leaves the old folded link absent; second injected EIO must
# leave the other folder link untouched and the earlier user backup preserved.
status=0
STOW_UNLINK_FAULT_AT=2 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/fail.out" 2>&1 || status=$?
BACKUPS=("$HOME_DIR"/.custom.backup.*)
if [ "$status" -eq 0 ] ||
  ! grep -q 'Could not remove link' "$TMP/fail.out" ||
  ! grep -Eq 'failed=1([^0-9]|$)' "$TMP/fail.out" ||
  [ -e "$HOME_DIR/.fold-a" ] ||
  [ -L "$HOME_DIR/.fold-a" ] ||
  [ ! -L "$HOME_DIR/.fold-b" ] ||
  [ "$(readlink "$HOME_DIR/.fold-b")" != "../repo/stow/demo/.fold-b" ] ||
  [ "$(wc -l <"$TMP/unlinks")" -ne 2 ] ||
  [ ! -f "${BACKUPS[0]}" ] ||
  ! grep -qx 'original user custom' "${BACKUPS[0]}" ||
  [ "$(wc -l <"$TMP/calls")" -ne 1 ]; then
  cat "$TMP/fail.out"
  echo 'FAIL: GNU Stow unlink EIO did not preserve the remaining folded link and backup'
  exit 1
fi

# Dry-run must not repair or mutate the failed partial state.
status=0
STOW_UNLINK_FAULT_AT=0 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$TMP/play.yml" --check >"$TMP/check.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  [ -e "$HOME_DIR/.fold-a" ] ||
  [ ! -L "$HOME_DIR/.fold-b" ] ||
  [ "$(wc -l <"$TMP/calls")" -ne 1 ] ||
  ! grep -q '재링크 예정' "$TMP/check.out" ||
  ! grep -qx 'original user custom' "${BACKUPS[0]}"; then
  cat "$TMP/check.out"
  echo 'FAIL: dry-run mutated the partial unlink failure state'
  exit 1
fi

# Normal retry must unfold both directories into real parents and leaf links.
status=0
STOW_UNLINK_FAULT_AT=0 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/retry.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  [ ! -d "$HOME_DIR/.fold-a" ] ||
  [ -L "$HOME_DIR/.fold-a" ] ||
  [ ! -d "$HOME_DIR/.fold-b" ] ||
  [ -L "$HOME_DIR/.fold-b" ] ||
  [ ! -L "$HOME_DIR/.fold-a/managed" ] ||
  [ ! -L "$HOME_DIR/.fold-b/managed" ] ||
  [ ! -L "$HOME_DIR/.custom" ] ||
  ! grep -qx 'managed a' "$HOME_DIR/.fold-a/managed" ||
  ! grep -qx 'managed b' "$HOME_DIR/.fold-b/managed" ||
  ! grep -qx 'original user custom' "${BACKUPS[0]}" ||
  [ "$(wc -l <"$TMP/calls")" -ne 2 ] ||
  ! grep -Eq 'changed=1([^0-9]|$)' "$TMP/retry.out"; then
  cat "$TMP/retry.out"
  echo 'FAIL: GNU Stow unlink recovery lost data or did not unfold correctly'
  exit 1
fi

# Clean repeated setup must not unlink/relink existing managed files.
status=0
STOW_UNLINK_FAULT_AT=0 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/clean.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  [ "$(wc -l <"$TMP/calls")" -ne 2 ] ||
  ! grep -Eq 'changed=0([^0-9]|$)' "$TMP/clean.out" ||
  ! grep -qx 'original user custom' "${BACKUPS[0]}"; then
  cat "$TMP/clean.out"
  echo 'FAIL: clean state was unnecessarily re-applied after unlink recovery'
  exit 1
fi
echo 'PASS: real GNU Stow unlink EIO preserves data, dry-run, retry, and idempotency'
