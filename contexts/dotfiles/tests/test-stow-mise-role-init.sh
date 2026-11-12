#!/usr/bin/env bash
# stow role의 ~/.config/mise 준비 단계 회귀: 외부 symlink는 건드리지 않고,
# 관리 링크는 유지하며, mkdir 중 부모 교체(TOCTOU)에도 사용자 데이터를 보존한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo '[WARNING] SKIP: ansible-playbook 필요 (stow mise role init 회귀)'
  exit 0
fi

export ANSIBLE_HOME="$TMP/ansible"
export ANSIBLE_LOCAL_TEMP="$TMP/local"
export ANSIBLE_REMOTE_TEMP="$TMP/remote"

mkdir -p "$TMP/repo/ansible/roles/stow/tasks" "$TMP/repo/bin/utils"

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
    "name": "Stow mise role init regression",
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

# Check mode is explicitly read-only and reports intended changes.
dry_home = tmp / "race-check-mode"
dry_home.mkdir()
helper.run("mise", str(dry_home), str(repo), True)
assert not (dry_home / ".config").exists()

print("PASS: Mise mkdir parent swap preserves data")
PY

echo 'PASS: stow role preserves foreign .config/mise links before mkdir and keeps managed links'
