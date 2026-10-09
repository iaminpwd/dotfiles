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
  [ "$(wc -l <"$TMP/calls")" -ne 1 ] ||
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
  [ "$(wc -l <"$TMP/calls")" -ne 1 ] ||
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
  [ "$(wc -l <"$TMP/calls")" -ne 1 ] ||
  ! grep -Eq 'changed=0([^0-9]|$)' "$TMP/retry.out"; then
  cat "$TMP/retry.out"
  echo 'FAIL: clean setup changed links or lost a backup'
  exit 1
fi
echo 'PASS: folded symlinks safely migrated without destructive Stow unlink'

# Simulate a concurrent user installing a regular file into an already-owned
# Stow symlink location AFTER GNU Stow has decided to unlink the symlink.
# GNU Stow's unlink cannot conditionally compare inode identity: -R would
# delete the newly arrived file. -S must not unlink correctly-owned leaves.
RACE="$TMP/unlink-swap-race"
mkdir -p "$RACE/stow/demo" "$RACE/home"
mkdir -p "$RACE/stow/demo/.fold-a"
printf 'managed owned\n' >"$RACE/stow/demo/.fold-a/managed"
printf 'managed fresh\n' >"$RACE/stow/demo/.fresh"
ln -s "../stow/demo/.fold-a" "$RACE/home/.fold-a"
cat >"$TMP/faultlib/StowConcurrentSwap.pm" <<'PERL'
package StowConcurrentSwap;
use strict;
use warnings;
BEGIN {
  *CORE::GLOBAL::unlink = sub {
    my $path = $_[0];
    if ($path =~ m{(?:^|/)\.fold-a$} && !$StowConcurrentSwap::swapped) {
      $StowConcurrentSwap::swapped = 1;
      rename($path, "$path.saved-managed-link")
        or die "failed to move disposable symlink: $!";
      open my $fh, '>', $path or die "failed to install disposable user file: $!";
      print {$fh} "valuable concurrent user file\n";
      close $fh;
      open my $log, '>', $ENV{STOW_CONCURRENT_SWAP_MARKER}
        or die "cannot record swap: $!";
      print {$log} "swapped\n";
      close $log;
    }
    return CORE::unlink($_[0]);
  };
}
1;
PERL
RACE_STOW=$(command -v stow)
# Replay the actual apply mode configured in the Ansible role.
if grep -Eq 'cmd: stow .* -R --no-folding' "$ROOT/ansible/roles/stow/tasks/package.yml"; then
  RACE_STOW_MODE=-R
elif grep -Eq 'cmd: stow .* -S --no-folding' "$ROOT/ansible/roles/stow/tasks/package.yml"; then
  RACE_STOW_MODE=-S
else
  echo 'FAIL: unexpected GNU Stow apply mode in Ansible role'
  exit 1
fi
race_status=0
(
  cd "$RACE/stow"
  PERL5LIB="$TMP/faultlib" PERL5OPT="-MStowConcurrentSwap" \
    STOW_CONCURRENT_SWAP_MARKER="$RACE/attempted" \
    "$RACE_STOW" "$RACE_STOW_MODE" --no-folding -t "$RACE/home" demo
) >"$RACE/output" 2>&1 || race_status=$?
if [ "$RACE_STOW_MODE" = -R ] && [ ! -f "$RACE/attempted" ]; then
  cat "$RACE/output"
  echo 'FAIL: real GNU Stow -R did not exercise a managed folded-link unlink'
  exit 1
fi
if [ -f "$RACE/attempted" ]; then
  # A version that does attempt unlink must preserve the injected user file
  # and stop, instead of treating it as the old Stow-owned symlink.
  if [ "$race_status" -eq 0 ] ||
    [ ! -f "$RACE/home/.fold-a" ] ||
    ! grep -qx 'valuable concurrent user file' "$RACE/home/.fold-a"; then
    cat "$RACE/output"
    echo 'FAIL: GNU Stow deleted a concurrently replaced user file'
    exit 1
  fi
else
  # A stow-only invocation does not need to remove existing owned symlinks.
  if [ "$race_status" -ne 0 ] ||
    [ ! -L "$RACE/home/.fold-a" ] ||
    [ ! -L "$RACE/home/.fresh" ] ||
    ! grep -qx 'managed owned' "$RACE/home/.fold-a/managed" ||
    ! grep -qx 'managed fresh' "$RACE/home/.fresh"; then
    cat "$RACE/output"
    echo 'FAIL: non-destructive Stow install did not converge'
    exit 1
  fi
fi
echo 'PASS: concurrent replacement cannot be deleted by Stow-owned-link removal'
# An attacker can swap a user HOME parent for an external symlink immediately
# before Stow's ordinary path-based symlink call. Use GNU Stow's actual Perl
# syscall from an isolated tree, never the runner's real HOME.
PARENT_RACE="$TMP/parent-swap"
mkdir -p "$PARENT_RACE/stow/demo/.config" "$PARENT_RACE/home/.config" \
  "$PARENT_RACE/external" "$TMP/faultlib"
printf 'managed content\n' >"$PARENT_RACE/stow/demo/.config/managed"
printf 'unrelated external secret\n' >"$PARENT_RACE/external/secret"
cat >"$TMP/faultlib/StowParentSwap.pm" <<'PERL'
package StowParentSwap;
use strict;
use warnings;
BEGIN {
  *CORE::GLOBAL::symlink = sub {
    my ($target, $dest) = @_;
    if (!$StowParentSwap::swapped && $dest =~ m{(?:^|/)\.config/managed$}) {
      $StowParentSwap::swapped = 1;
      my $home = $ENV{STOW_PARENT_SWAP_HOME};
      my $external = $ENV{STOW_PARENT_SWAP_EXTERNAL};
      rename("$home/.config", "$home/.config-preserved")
        or die "cannot move disposable parent: $!";
      CORE::symlink($external, "$home/.config")
        or die "cannot swap disposable parent: $!";
      open my $marker, '>', $ENV{STOW_PARENT_SWAP_MARKER}
        or die "cannot record injected swap: $!";
      print {$marker} "injected\n";
      close $marker;
    }
    return CORE::symlink($target, $dest);
  };
}
1;
PERL
(
  cd "$PARENT_RACE/stow"
  PERL5LIB="$TMP/faultlib" PERL5OPT="-MStowParentSwap" \
    STOW_PARENT_SWAP_HOME="$PARENT_RACE/home" \
    STOW_PARENT_SWAP_EXTERNAL="$PARENT_RACE/external" \
    STOW_PARENT_SWAP_MARKER="$PARENT_RACE/injected" \
    "$(command -v stow)" -S --no-folding -t "$PARENT_RACE/home" demo
) >"$PARENT_RACE/out" 2>&1 || true
if [ ! -f "$PARENT_RACE/injected" ]; then
  cat "$PARENT_RACE/out"
  echo 'FAIL: GNU Stow parent swap injection did not execute'
  exit 1
fi
if [ -L "$PARENT_RACE/external/managed" ]; then
  echo 'FAIL: GNU Stow followed swapped HOME parent and wrote an external symlink'
  exit 1
fi
if [ ! -f "$PARENT_RACE/external/secret" ]; then
  echo 'FAIL: an unrelated external file was removed during Stow apply'
  exit 1
fi
echo 'PASS: applying links cannot cross swapped HOME parent'
