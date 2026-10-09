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

mkdir -p "$TMP/repo/ansible/roles/stow/tasks" "$TMP/repo/bin/utils" \
  "$TMP/repo/mise" "$TMP/private" "$TMP/home-user" "$TMP/home-legacy"
printf 'legacy=true\n' >"$TMP/repo/mise/.mise.toml"
printf 'user=true\n' >"$TMP/private/mise.toml"

python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import json
import shutil
import sys

root, tmp = map(Path, sys.argv[1:])
for path in ("bin/utils/stow-safe-role-init.py", "bin/utils/stow-safe-install.py"):
    shutil.copy2(root / path, tmp / "repo" / path)
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

# The role must reject foreign shared-config symlinks before attempting
# the first mkdir; an external directory must remain untouched on failure.
FOREIGN_HOME="$TMP/home-foreign"
FOREIGN_STORE="$TMP/user-config-store"
mkdir -p "$FOREIGN_HOME" "$FOREIGN_STORE"
printf 'personal configuration\n' >"$FOREIGN_STORE/private.conf"
ln -s "../user-config-store" "$FOREIGN_HOME/.config"
status=0
STOW_TEST_HOME="$FOREIGN_HOME" ANSIBLE_ROLES_PATH="$TMP/repo/ansible/roles" \
  ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/foreign.out" 2>&1 || status=$?
if [ "$status" -eq 0 ] || [ ! -L "$FOREIGN_HOME/.config" ] ||
  [ "$(readlink "$FOREIGN_HOME/.config")" != "../user-config-store" ] ||
  [ -e "$FOREIGN_STORE/mise" ] ||
  [ ! -f "$FOREIGN_STORE/private.conf" ] ||
  ! grep -qF "외부 Mise 설정 디렉토리 링크 사전 차단" "$TMP/foreign.out"; then
  cat "$TMP/foreign.out"
  echo 'FAIL: stow role modified a foreign ~/.config before rejecting it'
  exit 1
fi

# Nested ~/.config/mise may likewise be a user-owned directory symlink.
NESTED_HOME="$TMP/home-nested"
NESTED_STORE="$TMP/user-mise-store"
mkdir -p "$NESTED_HOME/.config" "$NESTED_STORE"
printf 'personal configuration\n' >"$NESTED_STORE/config.toml"
ln -s "../../user-mise-store" "$NESTED_HOME/.config/mise"
status=0
STOW_TEST_HOME="$NESTED_HOME" ANSIBLE_ROLES_PATH="$TMP/repo/ansible/roles" \
  ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/nested.out" 2>&1 || status=$?
if [ "$status" -eq 0 ] || [ ! -L "$NESTED_HOME/.config/mise" ] ||
  [ "$(readlink "$NESTED_HOME/.config/mise")" != "../../user-mise-store" ] ||
  [ ! -f "$NESTED_STORE/config.toml" ]; then
  cat "$TMP/nested.out"
  echo 'FAIL: stow role altered an external ~/.config/mise symlink'
  exit 1
fi

# Previous Stow tree-folding may have created a symlink to *our* .config tree.
# The preflight must not block this valid managed link on upgrades.
MANAGED_HOME="$TMP/home-managed"
mkdir -p "$MANAGED_HOME" "$TMP/repo/stow/mise/.config/mise"
ln -s "../repo/stow/mise/.config" "$MANAGED_HOME/.config"
STOW_TEST_HOME="$MANAGED_HOME" ANSIBLE_ROLES_PATH="$TMP/repo/ansible/roles" \
  ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/managed.out" 2>&1 || {
  cat "$TMP/managed.out"
  echo 'FAIL: stow preflight incorrectly rejected an existing managed .config symlink'
  exit 1
}
if [ ! -L "$MANAGED_HOME/.config" ] ||
  [ "$(readlink "$MANAGED_HOME/.config")" != "../repo/stow/mise/.config" ] ||
  [ ! -d "$MANAGED_HOME/.config/mise" ]; then
  cat "$TMP/managed.out"
  echo 'FAIL: existing Stow-owned .config symlink was disturbed'
  exit 1
fi

# Deterministic TOCTOU at the ACTUAL safe role initialization boundary. An
# open HOME parent can be renamed outside HOME during mkdir(dir_fd=...);
# the role must detect it, never follow a swapped foreign parent, and retry
# after restoration without corrupting unrelated user content.
STOW_ROLE_HELPER="$TMP/repo/bin/utils/stow-safe-role-init.py" \
  STOW_ROLE_FIXTURE="$TMP" python3 - <<'PY'
import importlib.util
import os
from pathlib import Path

tmp = Path(os.environ["STOW_ROLE_FIXTURE"])
script = os.environ["STOW_ROLE_HELPER"]
spec = importlib.util.spec_from_file_location("stow_safe_role_init", script)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
repo = tmp / "repo"

race = tmp / "race-mise-mkdir"
home = race / "home"
external = race / "outside"
(home / ".config").mkdir(parents=True)
external.mkdir()
(external / "secret").write_bytes(b"external private settings\n")
real_mkdir = os.mkdir
real_symlink = os.symlink
swapped = [False]

def move_at_mkdir(name, *args, **kwargs):
    if name == "mise" and kwargs.get("dir_fd") is not None and not swapped[0]:
        swapped[0] = True
        os.rename(home / ".config", external / "moved")
        real_symlink(str(external), home / ".config")
    return real_mkdir(name, *args, **kwargs)

os.mkdir = move_at_mkdir
try:
    try:
        helper.run("mise", str(home), str(repo), False)
    except RuntimeError as exc:
        assert "HOME parent replaced" in str(exc), exc
    else:
        raise AssertionError("foreign HOME parent accepted after mkdir")
finally:
    os.mkdir = real_mkdir
assert swapped[0], "mkdir injection did not execute"
assert (external / "secret").read_bytes() == b"external private settings\n"
assert not (external / "mise").exists(), "followed swapped symlink into external dir"
assert (home / ".config").is_symlink()
(home / ".config").unlink()
os.rename(external / "moved", home / ".config")
helper.run("mise", str(home), str(repo), False)
assert (home / ".config/mise").is_dir()

# The Ansible legacy cleanup originally checked source identity in one task,
# then removed the pathname in a later task. Inject the same swap immediately
# before the staged rename. A regular user file must be returned, never
# deleted, and the original repository content must remain unchanged.
legacy_home = tmp / "race-legacy"
legacy_home.mkdir()
owned_target = repo / "mise/.mise.toml"
entry = legacy_home / ".mise.toml"
entry.symlink_to(owned_target)
original_rename = os.rename
replaced = [False]

def replace_at_move(source, dest, *args, **kwargs):
    if (source == ".mise.toml" and kwargs.get("src_dir_fd") is not None
            and not replaced[0]):
        replaced[0] = True
        entry.unlink()
        entry.write_bytes(b"concurrent user-owned mise settings\n")
    return original_rename(source, dest, *args, **kwargs)

os.rename = replace_at_move
try:
    try:
        helper.run("legacy", str(legacy_home), str(repo), False)
    except RuntimeError as exc:
        assert "restored user entry" in str(exc), exc
    else:
        raise AssertionError("concurrent user file deleted during legacy cleanup")
finally:
    os.rename = original_rename
assert replaced[0]
assert entry.read_bytes() == b"concurrent user-owned mise settings\n"
assert owned_target.read_bytes() == b"legacy=true\n"
assert not list(legacy_home.glob(".mise.toml.stow-stage-*"))

# Check mode is explicitly read-only and reports intended changes.
dry_home = tmp / "race-check-mode"
dry_home.mkdir()
helper.run("mise", str(dry_home), str(repo), True)
assert not (dry_home / ".config").exists()
entry.unlink()
entry.symlink_to(owned_target)
helper.run("legacy", str(legacy_home), str(repo), True)
assert entry.is_symlink(), "dry run removed the owned symlink"
helper.run("legacy", str(legacy_home), str(repo), False)
assert not entry.exists() and not entry.is_symlink()
assert owned_target.read_bytes() == b"legacy=true\n"

print("PASS: Mise mkdir parent swap and legacy file replacement preserve data")
PY

echo 'PASS: stow role preserves foreign .config/mise links before mkdir and keeps managed links'
