#!/usr/bin/env bash
# BSD readlink portability, drift preflight, safe apply failure ordering,
# per-package backup preservation, retry and idempotency in disposable HOME.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if ! command -v ansible-playbook >/dev/null 2>&1 || ! command -v stow >/dev/null 2>&1; then
  echo '[WARNING] SKIP: Ansible / GNU Stow unavailable'
  exit 0
fi
export ANSIBLE_HOME="$TMP/ansible" ANSIBLE_LOCAL_TEMP="$TMP/local" ANSIBLE_REMOTE_TEMP="$TMP/remote"
mkdir -p "$ANSIBLE_HOME" "$ANSIBLE_LOCAL_TEMP" "$ANSIBLE_REMOTE_TEMP" \
  "$TMP/repo/ansible/roles/stow/tasks" "$TMP/repo/stow/demo/.config/demo" \
  "$TMP/repo/bin/utils" "$TMP/home" "$TMP/fakebin"
# The drift task uses the same safe Python inventory/ownership logic as
# installation; include both the helper and GNU Stow's ignore matcher.
cp "$ROOT/bin/utils/stow-safe-install.py" "$ROOT/bin/utils/stow-filter-inventory.pl" "$TMP/repo/bin/utils/"
printf 'managed\n' >"$TMP/repo/stow/demo/.config/demo/config"

cat >"$TMP/fakebin/readlink" <<'STUB'
#!/bin/sh
if [ "${1:-}" = -f ]; then
  echo 'readlink: illegal option -- f' >&2
  exit 1
fi
exec /usr/bin/readlink "$@"
STUB
chmod +x "$TMP/fakebin/readlink"

python3 - "$ROOT" "$TMP" <<'PY'
import json
from pathlib import Path
import sys

root, tmp = map(Path, sys.argv[1:])
source = (root / "ansible/roles/stow/tasks/package.yml").read_text()
start = source.index("- name: 심볼릭 링크 드리프트(변경 필요 여부) 사전 판정")
end = source.index("- name: 안전한 파일 단위 심볼릭 링크 적용", start)
(tmp / "tasks.yml").write_text("---\n" + source[start:end].rstrip() + "\n")
play = [{
    "hosts": "localhost", "connection": "local", "gather_facts": False,
    "environment": {
        "PATH": str(tmp / "fakebin") + ":{{ lookup('env', 'PATH') }}",
        "STOW_TEST_FILTER_MODE": "{{ lookup('env', 'STOW_TEST_FILTER_MODE') }}",
        "STOW_TEST_PARTIAL_FILE": "{{ lookup('env', 'STOW_TEST_PARTIAL_FILE') }}",
    },
    "vars": {
        "role_path": str(tmp / "repo/ansible/roles/stow"),
        "ansible_env": {"HOME": str(tmp / "home")},
        "stow_package": {"path": str(tmp / "repo/stow/demo")},
    },
    "tasks": [
        {"ansible.builtin.import_tasks": str(tmp / "tasks.yml")},
        {"ansible.builtin.assert": {
            "that": ["stow_drift_check.stdout is defined",
                     "stow_drift_check.stdout | trim == '1'"],
        }},
    ],
}]
(tmp / "play.yml").write_text(json.dumps(play))
owned_play = json.loads(json.dumps(play))
owned_play[0]["tasks"][1]["ansible.builtin.assert"]["that"][1] = (
    "stow_drift_check.stdout | trim == '0'"
)
(tmp / "owned.yml").write_text(json.dumps(owned_play))
PY

status=0
ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/drift.out" 2>&1 || status=$?
if [ "$status" -ne 0 ]; then
  cat "$TMP/drift.out"
  echo 'FAIL: missing link drift not detected with BSD readlink'
  exit 1
fi

# secure installer는 symlink의 마지막 leaf까지 realpath하여 관리 링크를
# 판정한다. drift 검사도 같은 링크 체인을 깨끗한 상태로 인정해야 한다.
mkdir -p "$TMP/home/.config/demo"
ln -s "$TMP/repo/stow/demo/.config/demo/config" "$TMP/home/.config/demo/.alias"
ln -s .alias "$TMP/home/.config/demo/config"
status=0
ansible-playbook -i localhost, "$TMP/owned.yml" >"$TMP/owned.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] || [ ! -L "$TMP/home/.config/demo/config" ]; then
  cat "$TMP/owned.out"
  echo 'FAIL: secure installer considers the alias chain owned but drift reports changes'
  exit 1
fi
rm "$TMP/home/.config/demo/config" "$TMP/home/.config/demo/.alias"
echo 'PASS: 관리 대상 symlink 체인에 대한 드리프트 오탐 없음'

cat >"$TMP/fakebin/perl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "${STOW_TEST_FILTER_MODE:-}" in
partial) printf '%s\0' "$STOW_TEST_PARTIAL_FILE" >"${9}"; exit 77 ;;
empty) exit 77 ;;
esac
exec /usr/bin/perl "$@"
STUB
chmod +x "$TMP/fakebin/perl"
for mode in partial empty; do
  status=0
  STOW_TEST_FILTER_MODE="$mode" STOW_TEST_PARTIAL_FILE="$TMP/repo/stow/demo/.config/demo/config" \
    ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/find-$mode.out" 2>&1 || status=$?
  if [ "$status" -eq 0 ] ||
    ! grep -qF '[Hard Block] 안전한 Stow 링크 설치 실패' "$TMP/find-$mode.out" ||
    [ ! -f "$TMP/repo/stow/demo/.config/demo/config" ]; then
    cat "$TMP/find-$mode.out"
    echo "FAIL: $mode inventory failure bypassed drift gate"
    exit 1
  fi
done

# Reuse the *actual* package include -> backup -> drift -> secure apply order.
# The test-only python3 shim intercepts only the installer invocation. It
# models a partial error after the first leaf and leaves all other commands
# delegated to the original Python interpreter.
python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import json
import shutil
import sys

root, tmp = map(Path, sys.argv[1:])
multi = tmp / "multi"
role = multi / "repo/ansible/roles/stow/tasks"
source = multi / "repo/stow"
home = multi / "home"
fakebin = multi / "fakebin"
for directory in (role, source / "alpha", source / "beta", home,
                  fakebin, multi / "repo/bin/utils"):
    directory.mkdir(parents=True, exist_ok=True)
(source / "alpha/.a-one").write_text("managed one\n")
(source / "alpha/.a-two").write_text("managed two\n")
(source / "beta/.beta").write_text("managed beta\n")
(home / ".a-one").write_text("original one\n")
(home / ".beta").write_text("original beta\n")
main = (root / "ansible/roles/stow/tasks/main.yml").read_text()
marker = "- name: Stow 패키지별 백업·드리프트 판정·적용"
(role / "main.yml").write_text("---\n" + main[main.index(marker):])
for path in ("ansible/roles/stow/tasks/package.yml",
             "bin/utils/stow-backup.sh",
             "bin/utils/stow-filter-inventory.pl",
             "bin/utils/stow-safe-backup.py",
             "bin/utils/stow-safe-install.py"):
    shutil.copy2(root / path, multi / "repo" / path)
(fakebin / "python3").write_text("""#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == */stow-safe-install.py && "${2:-}" != --check-drift ]]; then
  pkg=$3
  printf '%s\\n' "$pkg" >>"$STOW_MULTI_LOG"
  if [ "$pkg" = alpha ] && [ "$STOW_MULTI_FAIL" = 1 ]; then
    ln -s ../repo/stow/alpha/.a-one "$STOW_MULTI_HOME/.a-one"
    exit 17
  fi
fi
exec "$STOW_REAL_PYTHON" "$@"
""")
(fakebin / "python3").chmod(0o755)
play = [{
    "hosts": "localhost", "connection": "local", "gather_facts": False,
    "environment": {
        "PATH": str(fakebin) + ":{{ lookup('env', 'PATH') }}",
        "HOME": str(home),
        "STOW_REAL_PYTHON": sys.executable,
        "STOW_MULTI_LOG": str(multi / "installer-calls"),
        "STOW_MULTI_HOME": str(home),
        "STOW_MULTI_FAIL": "{{ lookup('env', 'STOW_MULTI_FAIL') }}",
    },
    "vars": {
        "ansible_env": {"HOME": str(home)},
        "stow_dirs": {"files": [
            {"path": str(source / "alpha")},
            {"path": str(source / "beta")},
        ]},
    },
    "roles": ["stow"],
}]
(multi / "play.yml").write_text(json.dumps(play))
PY

MULTI="$TMP/multi"
ROLES="$MULTI/repo/ansible/roles"
status=0
STOW_MULTI_FAIL=1 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$MULTI/play.yml" >"$MULTI/failed.out" 2>&1 || status=$?
ALPHA_BACKUPS=("$MULTI/home"/.a-one.backup.*)
BETA_BACKUPS=("$MULTI/home"/.beta.backup.*)
if [ "$status" -eq 0 ] ||
  ! grep -Eq 'failed=1([^0-9]|$)' "$MULTI/failed.out" ||
  [ ! -L "$MULTI/home/.a-one" ] || [ -e "$MULTI/home/.a-two" ] ||
  [ ! -f "${ALPHA_BACKUPS[0]}" ] ||
  ! grep -qx 'original one' "${ALPHA_BACKUPS[0]}" ||
  ! grep -qx 'original beta' "$MULTI/home/.beta" ||
  [ -e "${BETA_BACKUPS[0]}" ] ||
  [ "$(wc -l <"$MULTI/installer-calls")" -ne 1 ]; then
  cat "$MULTI/failed.out"
  echo 'FAIL: partial install touched later package or lost existing data'
  exit 1
fi

status=0
STOW_MULTI_FAIL=0 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$MULTI/play.yml" --check >"$MULTI/check.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  ! grep -q '재링크 예정' "$MULTI/check.out" ||
  ! grep -qx 'original beta' "$MULTI/home/.beta" ||
  [ -e "${BETA_BACKUPS[0]}" ] ||
  [ "$(wc -l <"$MULTI/installer-calls")" -ne 1 ]; then
  cat "$MULTI/check.out"
  echo 'FAIL: dry-run mutated partial install or lost user files'
  exit 1
fi

status=0
STOW_MULTI_FAIL=0 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$MULTI/play.yml" >"$MULTI/retry.out" 2>&1 || status=$?
BETA_BACKUPS=("$MULTI/home"/.beta.backup.*)
if [ "$status" -ne 0 ] ||
  [ ! -L "$MULTI/home/.a-one" ] ||
  [ ! -L "$MULTI/home/.a-two" ] ||
  [ ! -L "$MULTI/home/.beta" ] ||
  ! grep -qx 'original one' "${ALPHA_BACKUPS[0]}" ||
  ! grep -qx 'original beta' "${BETA_BACKUPS[0]}" ||
  [ "$(wc -l <"$MULTI/installer-calls")" -ne 3 ] ||
  ! grep -Eq 'changed=2([^0-9]|$)' "$MULTI/retry.out"; then
  cat "$MULTI/retry.out"
  echo 'FAIL: partial failure did not converge safely on retry'
  exit 1
fi

status=0
STOW_MULTI_FAIL=0 ANSIBLE_ROLES_PATH="$ROLES" \
  ansible-playbook -i localhost, "$MULTI/play.yml" >"$MULTI/clean.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  [ "$(wc -l <"$MULTI/installer-calls")" -ne 3 ] ||
  ! grep -Eq 'changed=0([^0-9]|$)' "$MULTI/clean.out"; then
  cat "$MULTI/clean.out"
  echo 'FAIL: clean setup unnecessarily invoked installer'
  exit 1
fi
echo 'PASS: read-only drift, partial inventory failure, secure apply ordering and retry'
