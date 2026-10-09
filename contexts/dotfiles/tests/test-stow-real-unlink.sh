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

# Unexpected GNU Stow unlink of a package-owned folded link returns EIO;
# the safe stow-only deployment must never reach this syscall.
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
shutil.copy2(root / "bin/utils/stow-filter-inventory.pl",
             repo / "bin/utils/stow-filter-inventory.pl")
shutil.copy2(root / "bin/utils/stow-safe-backup.py",
             repo / "bin/utils/stow-safe-backup.py")
shutil.copy2(root / "bin/utils/stow-safe-install.py",
             repo / "bin/utils/stow-safe-install.py")
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

# Historical folded links must be moved with the safe backup helper, not
# unlinked by GNU Stow while a user may concurrently replace the pathname.
status=0
STOW_UNLINK_FAULT_AT=1 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/install.out" 2>&1 || status=$?
FOLD_A_BACKUPS=("$HOME_DIR"/.fold-a.backup.*)
FOLD_B_BACKUPS=("$HOME_DIR"/.fold-b.backup.*)
CUSTOM_BACKUPS=("$HOME_DIR"/.custom.backup.*)
if [ "$status" -ne 0 ] ||
  [ ! -d "$HOME_DIR/.fold-a" ] || [ -L "$HOME_DIR/.fold-a" ] ||
  [ ! -d "$HOME_DIR/.fold-b" ] || [ -L "$HOME_DIR/.fold-b" ] ||
  [ ! -L "$HOME_DIR/.fold-a/managed" ] ||
  [ ! -L "$HOME_DIR/.fold-b/managed" ] ||
  [ ! -L "$HOME_DIR/.custom" ] ||
  [ ! -L "${FOLD_A_BACKUPS[0]}" ] ||
  [ ! -L "${FOLD_B_BACKUPS[0]}" ] ||
  [ ! -f "${CUSTOM_BACKUPS[0]}" ] ||
  [ "$(readlink "${FOLD_A_BACKUPS[0]}")" != "../repo/stow/demo/.fold-a" ] ||
  [ "$(readlink "${FOLD_B_BACKUPS[0]}")" != "../repo/stow/demo/.fold-b" ] ||
  ! grep -qx 'original user custom' "${CUSTOM_BACKUPS[0]}" ||
  [ -s "$TMP/unlinks" ] ||
  [ -e "$TMP/calls" ] ||
  ! grep -Eq 'changed=1([^0-9]|$)' "$TMP/install.out"; then
  cat "$TMP/install.out"
  echo 'FAIL: safe folded-link migration or no-unlink install failed'
  exit 1
fi

# --check must not mutate the newly migrated links or older user backups.
status=0
STOW_UNLINK_FAULT_AT=1 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$TMP/play.yml" --check >"$TMP/check.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  [ ! -L "$HOME_DIR/.fold-a/managed" ] ||
  [ ! -L "$HOME_DIR/.fold-b/managed" ] ||
  [ ! -L "$HOME_DIR/.custom" ] ||
  [ -e "$TMP/calls" ] ||
  [ -s "$TMP/unlinks" ] ||
  ! grep -qx 'original user custom' "${CUSTOM_BACKUPS[0]}"; then
  cat "$TMP/check.out"
  echo 'FAIL: dry-run modified migrated links or user backups'
  exit 1
fi

# Repeated setup must not invoke GNU Stow or change any existing backup.
status=0
STOW_UNLINK_FAULT_AT=1 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/retry.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  [ ! -L "$HOME_DIR/.fold-a/managed" ] ||
  [ ! -L "$HOME_DIR/.fold-b/managed" ] ||
  [ ! -L "$HOME_DIR/.custom" ] ||
  ! grep -qx 'original user custom' "${CUSTOM_BACKUPS[0]}" ||
  [ -s "$TMP/unlinks" ] ||
  [ -e "$TMP/calls" ] ||
  ! grep -Eq 'changed=0([^0-9]|$)' "$TMP/retry.out"; then
  cat "$TMP/retry.out"
  echo 'FAIL: clean setup changed links or lost a backup'
  exit 1
fi
echo 'PASS: folded symlinks safely migrated without destructive Stow unlink'

# The actual role must never delegate mutating apply operations to GNU Stow.
if ! grep -q 'stow-safe-install.py' "$ROOT/ansible/roles/stow/tasks/package.yml" ||
  grep -Eq 'cmd: stow .* -(S|R) --no-folding' "$ROOT/ansible/roles/stow/tasks/package.yml"; then
  echo 'FAIL: role still performs path-based GNU Stow writes'
  exit 1
fi
# The secure installer must not follow a HOME parent swapped to an external
# symlink between an O_NOFOLLOW directory open and os.symlink(dir_fd=...).
PARENT_RACE="$TMP/parent-swap"
mkdir -p "$PARENT_RACE/stow/demo/.config" "$PARENT_RACE/home/.config" \
  "$PARENT_RACE/external"
printf 'managed content\n' >"$PARENT_RACE/stow/demo/.config/managed"
printf 'unrelated external secret\n' >"$PARENT_RACE/external/secret"
STOW_SAFE_INSTALL="$ROOT/bin/utils/stow-safe-install.py" \
  STOW_SWAP_TEST_ROOT="$PARENT_RACE" python3 - <<'PY'
import importlib.util
import os
from pathlib import Path

root = Path(os.environ["STOW_SWAP_TEST_ROOT"])
home = root / "home"
external = root / "external"
helper_path = os.environ["STOW_SAFE_INSTALL"]
spec = importlib.util.spec_from_file_location("stow_safe_install", helper_path)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

original = os.symlink
swapped = [False]

def swap_before_create(target, link_name, *args, **kwargs):
    if link_name == "managed" and kwargs.get("dir_fd") is not None and not swapped[0]:
        swapped[0] = True
        os.rename(home / ".config", home / ".config-preserved")
        original(str(external), home / ".config")
    return original(target, link_name, *args, **kwargs)

os.symlink = swap_before_create
try:
    try:
        helper.install(str(root / "stow"), "demo", str(home))
    except RuntimeError as exc:
        assert "HOME parent replaced" in str(exc), exc
    else:
        raise AssertionError("swapped HOME parent did not hard block")
finally:
    os.symlink = original

assert swapped[0], "injected race was not exercised"
assert (external / "secret").read_bytes() == b"unrelated external secret\n"
assert not (external / "managed").exists()
assert (home / ".config").is_symlink()
assert (home / ".config-preserved").is_dir()

# Concurrent user creation after preflight must not be overwritten by install.
fresh = root / "fresh"
(fresh / "stow/demo/.config").mkdir(parents=True)
(fresh / "home/.config").mkdir(parents=True)
(fresh / "stow/demo/.config/managed").write_bytes(b"managed\n")
original = os.symlink
injected = [False]

def create_user_file_first(target, link_name, *args, **kwargs):
    if link_name == "managed" and kwargs.get("dir_fd") is not None and not injected[0]:
        injected[0] = True
        (fresh / "home/.config/managed").write_bytes(b"concurrent user contents\n")
    return original(target, link_name, *args, **kwargs)

os.symlink = create_user_file_first
try:
    try:
        helper.install(str(fresh / "stow"), "demo", str(fresh / "home"))
    except RuntimeError as exc:
        assert "concurrent HOME entry blocks" in str(exc), exc
    else:
        raise AssertionError("concurrent new user file was not blocked")
finally:
    os.symlink = original
assert injected[0]
assert (fresh / "home/.config/managed").read_bytes() == b"concurrent user contents\n"

# A correct owned symlink must remain the very same inode on repeated setup.
owned = root / "owned"
(owned / "stow/demo").mkdir(parents=True)
(owned / "home").mkdir()
(owned / "stow/demo/.managed").write_bytes(b"managed\n")
link = owned / "home/.managed"
link.symlink_to("../stow/demo/.managed")
prior = link.lstat()
helper.install(str(owned / "stow"), "demo", str(owned / "home"))
after = link.lstat()
assert (prior.st_dev, prior.st_ino) == (after.st_dev, after.st_ino)

# macOS exposes temp roots through aliases such as /var -> /private/var.
# A symlink in a HOME ancestor (not the HOME leaf) must not make the
# relative link target dangle when source and target spellings differ.
alias_root = root / "ancestor-alias"
real = alias_root / "nested/actual"
(real / "stow/demo/.config").mkdir(parents=True)
(real / "home").mkdir()
(real / "stow/demo/.config/managed").write_bytes(b"alias-managed\n")
(alias_root / "short").symlink_to("nested/actual", target_is_directory=True)
helper.install(str(real / "stow"), "demo", str(alias_root / "short/home"))
installed = real / "home/.config/managed"
assert installed.is_symlink(), installed
assert installed.read_bytes() == b"alias-managed\\n", os.readlink(installed)

print("PASS: swapped parents, concurrent leaf creation and aliased ancestor paths preserve data")
PY
