#!/usr/bin/env bash
# packages -> stow 순서에서 macOS/BSD readlink 환경의 드리프트 판정이 정확한지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo '[WARNING] SKIP: ansible-playbook 필요 (stow readlink ordering 회귀)'
  exit 0
fi

export ANSIBLE_HOME="$TMP/ansible"
export ANSIBLE_LOCAL_TEMP="$TMP/local"
export ANSIBLE_REMOTE_TEMP="$TMP/remote"

ROLE="$TMP/repo/ansible/roles/stow"
PKG="$TMP/repo/stow/demo"
HOME_DIR="$TMP/home"
FAKEBIN="$TMP/fakebin"
mkdir -p "$ROLE/tasks" "$PKG/.config/demo" "$HOME_DIR" "$FAKEBIN"
printf 'managed\n' >"$PKG/.config/demo/config"

# macOS 기본 BSD readlink처럼 -f를 지원하지 않되 plain readlink는 동작하게 한다.
cat >"$FAKEBIN/readlink" <<'STUB'
#!/bin/sh
if [ "${1:-}" = "-f" ]; then
  echo 'readlink: illegal option -- f' >&2
  exit 1
fi
exec /usr/bin/readlink "$@"
STUB
chmod +x "$FAKEBIN/readlink"

python3 - "$ROOT" "$TMP" <<'PY'
from pathlib import Path
import json
import sys

root, tmp = map(Path, sys.argv[1:])
source = (root / "ansible/roles/stow/tasks/package.yml").read_text()

start_marker = "- name: 심볼릭 링크 드리프트(변경 필요 여부) 사전 판정"
end_marker = "- name: GNU Stow 를 통해 홈 디렉토리에 심볼릭 링크 적용"
start = source.index(start_marker)
end = source.index(end_marker, start)
subset = source[start:end].rstrip() + "\n"
(tmp / "tasks.yml").write_text("---\n" + subset)

play = [{
    "name": "Stow cross-component ordering regression",
    "hosts": "localhost",
    "connection": "local",
    "gather_facts": False,
    "environment": {
        "PATH": str(tmp / "fakebin") + ":/usr/bin:/bin",
        "STOW_TEST_FIND_MODE": "{{ lookup('env', 'STOW_TEST_FIND_MODE') }}",
        "STOW_TEST_PARTIAL_FILE": "{{ lookup('env', 'STOW_TEST_PARTIAL_FILE') }}",
    },
    "vars": {
        "role_path": str(tmp / "repo/ansible/roles/stow"),
        "ansible_env": {"HOME": str(tmp / "home")},
        "stow_package": {"path": str(tmp / "repo/stow/demo")},
    },
    "tasks": [
        {
            "name": "Import actual stow drift detector",
            "ansible.builtin.import_tasks": str(tmp / "tasks.yml"),
        },
        {
            "name": "Assert missing target is detected as drift",
            "ansible.builtin.assert": {
                "that": [
                    "stow_drift_check.stdout is defined",
                    "stow_drift_check.stdout | trim == '1'",
                ],
                "fail_msg": "stow drift detector treated BSD readlink -f failure as no drift",
            },
        },
    ],
}]
(tmp / "play.yml").write_text(json.dumps(play))

# Import the actual package detector AND Stow apply task to assert repeat-install
# behavior. No production roles or real HOME are modified by this fixture.
apply_start = source.index(end_marker)
apply_end = source.index(
    "- name: 재링크 예정 stow 패키지 안내 (dry-run 전용)",
    apply_start,
)
(tmp / "apply-tasks.yml").write_text(
    "---\n" + source[start:apply_end].rstrip() + "\n"
)
apply_play = [{
    "name": "Stow actual apply gating regression",
    "hosts": "localhost",
    "connection": "local",
    "gather_facts": False,
    "environment": {
        "PATH": str(tmp / "fakebin") + ":/usr/bin:/bin",
        "STOW_TEST_STOW_LOG": str(tmp / "stow-calls"),
        "STOW_TEST_STOW_HOME": str(tmp / "home"),
        "STOW_TEST_STOW_SOURCE": str(tmp / "repo/stow/demo/.config/demo/config"),
        "STOW_TEST_STOW_EXIT": "{{ lookup('env', 'STOW_TEST_STOW_EXIT') }}",
    },
    "vars": {
        "role_path": str(tmp / "repo/ansible/roles/stow"),
        "ansible_env": {"HOME": str(tmp / "home")},
        "stow_package": {"path": str(tmp / "repo/stow/demo")},
    },
    "tasks": [{
        "name": "Import actual Stow detection and apply tasks",
        "ansible.builtin.import_tasks": str(tmp / "apply-tasks.yml"),
    }],
}]
(tmp / "apply-play.yml").write_text(json.dumps(apply_play))
PY

status=0
ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/out" 2>&1 || status=$?
if [ "$status" -ne 0 ]; then
  cat "$TMP/out"
  exit "$status"
fi

# Simulate a failing find command inside the real Ansible drift task.
# A partial NUL-delimited output must not yield a successful "drift=1",
# and an empty failed inventory must not be reported as "drift=0".
cat >"$FAKEBIN/find" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "${STOW_TEST_FIND_MODE:-}" in
partial)
  printf '%s\0' "$STOW_TEST_PARTIAL_FILE"
  exit 77
  ;;
empty)
  exit 77
  ;;
esac
exec /usr/bin/find "$@"
STUB
chmod +x "$FAKEBIN/find"

for mode in partial empty; do
  status=0
  STOW_TEST_FIND_MODE="$mode" \
    STOW_TEST_PARTIAL_FILE="$PKG/.config/demo/config" \
    ansible-playbook -i localhost, "$TMP/play.yml" >"$TMP/find-$mode.out" 2>&1 || status=$?
  if [ "$status" -eq 0 ] ||
    ! grep -qF "Stow 소스 탐색 실패 (drift)" "$TMP/find-$mode.out" ||
    ! grep -qF "심볼릭 링크 드리프트(변경 필요 여부) 사전 판정" "$TMP/find-$mode.out" ||
    [ ! -f "$PKG/.config/demo/config" ]; then
    cat "$TMP/find-$mode.out"
    echo "FAIL: find $mode failure did not stop the Stow drift task"
    exit 1
  fi
done

# Run the *actual* Stow apply task with a fake stow binary. The fake
# command creates a valid link on success, tracks invocations, and can simulate
# an immediate command failure without touching user files.
cat >"$FAKEBIN/stow" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'called\n' >>"$STOW_TEST_STOW_LOG"
if [ "${STOW_TEST_STOW_EXIT:-}" = fail ]; then
  exit 17
fi
mkdir -p "$STOW_TEST_STOW_HOME/.config/demo"
ln -s "$STOW_TEST_STOW_SOURCE" "$STOW_TEST_STOW_HOME/.config/demo/config"
STUB
chmod +x "$FAKEBIN/stow"

# A failed first application must make the play fail, without false success.
status=0
STOW_TEST_STOW_EXIT=fail ansible-playbook -i localhost, "$TMP/apply-play.yml" \
  >"$TMP/apply-failure.out" 2>&1 || status=$?
if [ "$status" -eq 0 ] ||
  [ -e "$HOME_DIR/.config/demo/config" ] ||
  [ "$(wc -l <"$TMP/stow-calls")" -ne 1 ]; then
  cat "$TMP/apply-failure.out"
  echo 'FAIL: failed Stow application was silently accepted'
  exit 1
fi

# On the next run there is drift, so the real task must invoke Stow once,
# create the link, and correctly report changed=1.
status=0
ansible-playbook -i localhost, "$TMP/apply-play.yml" \
  >"$TMP/apply-first.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  [ ! -L "$HOME_DIR/.config/demo/config" ] ||
  [ "$(readlink "$HOME_DIR/.config/demo/config")" != "$PKG/.config/demo/config" ] ||
  [ "$(wc -l <"$TMP/stow-calls")" -ne 2 ] ||
  ! grep -Eq 'changed=1([^0-9]|$)' "$TMP/apply-first.out"; then
  cat "$TMP/apply-first.out"
  echo 'FAIL: drifted package was not applied and marked changed'
  exit 1
fi

# A clean second run must skip Stow entirely and report changed=0. The stub
# deliberately fails if called a second time against an existing target.
status=0
ansible-playbook -i localhost, "$TMP/apply-play.yml" \
  >"$TMP/apply-clean.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  [ "$(wc -l <"$TMP/stow-calls")" -ne 2 ] ||
  ! grep -Eq 'changed=0([^0-9]|$)' "$TMP/apply-clean.out" ||
  [ "$(readlink "$HOME_DIR/.config/demo/config")" != "$PKG/.config/demo/config" ]; then
  cat "$TMP/apply-clean.out"
  echo 'FAIL: clean package needlessly invoked Stow or misreported changed'
  exit 1
fi


# Test the actual role include -> backup -> drift -> apply order under an
# injected partial Stow failure. Every path is inside the disposable TMP.
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
for directory in (role, source / "alpha", source / "beta", home, fakebin,
                  multi / "repo/bin/utils"):
    directory.mkdir(parents=True, exist_ok=True)
(source / "alpha/.a-one").write_text("managed one\n")
(source / "alpha/.a-two").write_text("managed two\n")
(source / "beta/.beta").write_text("managed beta\n")
(home / ".a-one").write_text("original one\n")
(home / ".beta").write_text("original beta\n")
main = (root / "ansible/roles/stow/tasks/main.yml").read_text()
marker = "- name: Stow 패키지별 백업·드리프트 판정·적용"
(role / "main.yml").write_text("---\n" + main[main.index(marker):])
shutil.copy2(root / "ansible/roles/stow/tasks/package.yml", role / "package.yml")
shutil.copy2(root / "bin/utils/stow-backup.sh",
             multi / "repo/bin/utils/stow-backup.sh")
(fakebin / "stow").write_text("""#!/usr/bin/env bash
set -euo pipefail
pkg=''
for arg in "$@"; do pkg="$arg"; done
printf '%s\\n' "$pkg" >>"$STOW_MULTI_LOG"
case "$pkg" in
alpha)
  if [ ! -L "$STOW_MULTI_HOME/.a-one" ]; then
    ln -s ../repo/stow/alpha/.a-one "$STOW_MULTI_HOME/.a-one"
  fi
  if [ "$STOW_MULTI_FAIL" = 1 ]; then exit 17; fi
  if [ ! -L "$STOW_MULTI_HOME/.a-two" ]; then
    ln -s ../repo/stow/alpha/.a-two "$STOW_MULTI_HOME/.a-two"
  fi
  ;;
beta)
  if [ ! -L "$STOW_MULTI_HOME/.beta" ]; then
    ln -s ../repo/stow/beta/.beta "$STOW_MULTI_HOME/.beta"
  fi
  ;;
*) exit 98 ;;
esac
""")
(fakebin / "stow").chmod(0o755)
play = [{
    "hosts": "localhost", "connection": "local", "gather_facts": False,
    "environment": {
        "PATH": str(fakebin) + ":/usr/bin:/bin",
        "STOW_MULTI_LOG": str(multi / "stow-calls"),
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
MULTI_ROLES="$MULTI/repo/ansible/roles"
status=0
STOW_MULTI_FAIL=1 ANSIBLE_ROLES_PATH="$MULTI_ROLES" \
  ansible-playbook -i localhost, "$MULTI/play.yml" \
  >"$MULTI/failed.out" 2>&1 || status=$?
ALPHA_BACKUPS=("$MULTI/home"/.a-one.backup.*)
BETA_BACKUPS=("$MULTI/home"/.beta.backup.*)
if [ "$status" -eq 0 ] ||
  ! grep -Eq 'failed=1([^0-9]|$)' "$MULTI/failed.out" ||
  [ ! -L "$MULTI/home/.a-one" ] ||
  [ -e "$MULTI/home/.a-two" ] ||
  [ ! -f "${ALPHA_BACKUPS[0]}" ] ||
  ! grep -qx 'original one' "${ALPHA_BACKUPS[0]}" ||
  ! grep -qx 'original beta' "$MULTI/home/.beta" ||
  [ -e "${BETA_BACKUPS[0]}" ] ||
  [ "$(wc -l <"$MULTI/stow-calls")" -ne 1 ] ||
  [ "$(cat "$MULTI/stow-calls")" != alpha ]; then
  cat "$MULTI/failed.out"
  echo 'FAIL: partial Stow failure preemptively backed up untouched package'
  exit 1
fi

status=0
STOW_MULTI_FAIL=0 ANSIBLE_ROLES_PATH="$MULTI_ROLES" \
  ansible-playbook -i localhost, "$MULTI/play.yml" --check \
  >"$MULTI/check.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  ! grep -q '재링크 예정' "$MULTI/check.out" ||
  ! grep -qx 'original beta' "$MULTI/home/.beta" ||
  [ -e "${BETA_BACKUPS[0]}" ] ||
  [ "$(wc -l <"$MULTI/stow-calls")" -ne 1 ]; then
  cat "$MULTI/check.out"
  echo 'FAIL: dry-run changed user data or missed partial drift'
  exit 1
fi

status=0
STOW_MULTI_FAIL=0 ANSIBLE_ROLES_PATH="$MULTI_ROLES" \
  ansible-playbook -i localhost, "$MULTI/play.yml" \
  >"$MULTI/retry.out" 2>&1 || status=$?
BETA_BACKUPS=("$MULTI/home"/.beta.backup.*)
if [ "$status" -ne 0 ] ||
  ! grep -qx 'original one' "${ALPHA_BACKUPS[0]}" ||
  ! grep -qx 'original beta' "${BETA_BACKUPS[0]}" ||
  [ ! -L "$MULTI/home/.a-one" ] ||
  [ ! -L "$MULTI/home/.a-two" ] ||
  [ ! -L "$MULTI/home/.beta" ] ||
  [ "$(wc -l <"$MULTI/stow-calls")" -ne 3 ] ||
  ! grep -Eq 'changed=2([^0-9]|$)' "$MULTI/retry.out"; then
  cat "$MULTI/retry.out"
  echo 'FAIL: retry did not preserve backups and finish both packages'
  exit 1
fi

status=0
STOW_MULTI_FAIL=0 ANSIBLE_ROLES_PATH="$MULTI_ROLES" \
  ansible-playbook -i localhost, "$MULTI/play.yml" \
  >"$MULTI/clean.out" 2>&1 || status=$?
if [ "$status" -ne 0 ] ||
  [ "$(wc -l <"$MULTI/stow-calls")" -ne 3 ] ||
  ! grep -Eq 'changed=0([^0-9]|$)' "$MULTI/clean.out"; then
  cat "$MULTI/clean.out"
  echo 'FAIL: clean retry re-applied already correct packages'
  exit 1
fi
echo 'PASS: partial Stow failure preserves untouched package, retry and dry-run safe'

echo 'PASS: Stow apply fails on command error, runs on drift, skips clean package, and supports BSD readlink'
