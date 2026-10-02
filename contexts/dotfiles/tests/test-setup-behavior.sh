#!/usr/bin/env bash
# 설치 진입점의 인자 전달과 로컬 시크릿 권한, Git 공유 설정 정책을 검증한다.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"
cat >"$TMP/bin/ansible-playbook" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$SETUP_ARGS"
STUB
chmod +x "$TMP/bin/ansible-playbook"
PATH="$TMP/bin:$PATH" SETUP_ARGS="$TMP/args" bash "$ROOT/bin/utils/run-setup.sh" --check --tags stow </dev/null
for arg in --check --tags stow; do
  grep -qx -- "$arg" "$TMP/args"
done
if grep -q -- --ask-become-pass "$TMP/args"; then exit 1; fi
echo 'PASS: 비대화형 설치와 dry-run 인자 전달'

# bootstrap의 Linux 권한 상승 경로를 실제 함수에서 추출해 검증한다.
# GitHub-hosted runner에는 sudo가 항상 있어 "root + sudo 없음" fresh/minimal 환경이
# bootstrap smoke만으로는 재현되지 않는다. 함수 본문을 복제하지 않고 원본을 source해
# root 직접 실행 / 일반 사용자 sudo / 권한 상승 수단 없음의 세 상태를 고정한다.
awk '/^_run_as_root\(\) \{/{capture=1} capture{print} capture && /^}/{exit}' "$ROOT/bootstrap.sh" >"$TMP/run-as-root.sh"
grep -q '^_run_as_root() {' "$TMP/run-as-root.sh"

make_id() {
  local dir=$1 uid=$2
  mkdir -p "$dir"
  cat >"$dir/id" <<STUB
#!/bin/sh
echo "$uid"
STUB
  chmod +x "$dir/id"
}
make_pkgcmd() {
  local dir=$1
  cat >"$dir/pkgcmd" <<'STUB'
#!/bin/sh
printf 'pkg:%s\n' "$*" >>"$PRIV_LOG"
STUB
  chmod +x "$dir/pkgcmd"
}

ROOT_BIN="$TMP/priv-root"
make_id "$ROOT_BIN" 0
make_pkgcmd "$ROOT_BIN"
PRIV_LOG="$TMP/priv-root.log" PATH="$ROOT_BIN" /bin/bash -c 'source "$1"; _run_as_root pkgcmd root-direct' _ "$TMP/run-as-root.sh"
grep -qx 'pkg:root-direct' "$TMP/priv-root.log"
echo 'PASS: root + sudo 없음은 시스템 명령을 직접 실행'

SUDO_BIN="$TMP/priv-sudo"
make_id "$SUDO_BIN" 1000
make_pkgcmd "$SUDO_BIN"
cat >"$SUDO_BIN/sudo" <<'STUB'
#!/bin/sh
printf 'sudo:%s\n' "$*" >>"$PRIV_LOG"
"$@"
STUB
chmod +x "$SUDO_BIN/sudo"
PRIV_LOG="$TMP/priv-sudo.log" PATH="$SUDO_BIN" /bin/bash -c 'source "$1"; _run_as_root pkgcmd via-sudo' _ "$TMP/run-as-root.sh"
grep -qx 'sudo:pkgcmd via-sudo' "$TMP/priv-sudo.log"
grep -qx 'pkg:via-sudo' "$TMP/priv-sudo.log"
echo 'PASS: non-root + sudo는 sudo를 통해 실행'

NOSUDO_BIN="$TMP/priv-nosudo"
make_id "$NOSUDO_BIN" 1000
make_pkgcmd "$NOSUDO_BIN"
status=0
out=$(PRIV_LOG="$TMP/priv-nosudo.log" PATH="$NOSUDO_BIN" /bin/bash -c 'source "$1"; _run_as_root pkgcmd blocked' _ "$TMP/run-as-root.sh" 2>&1) || status=$?
[ "$status" -ne 0 ]
[[ "$out" == *"root 권한 또는 sudo가 필요합니다"* ]]
[ ! -e "$TMP/priv-nosudo.log" ]
echo 'PASS: non-root + sudo 없음은 명확한 오류로 차단'

grep -q '_run_as_root apt-get update -qq' "$ROOT/bootstrap.sh"
grep -q '_run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install' "$ROOT/bootstrap.sh"
grep -q '_run_as_root dnf install' "$ROOT/bootstrap.sh"
! grep -Eq '^[[:space:]]+sudo (apt-get|dnf)' "$ROOT/bootstrap.sh"
echo 'PASS: Linux bootstrap 패키지 설치가 권한 래퍼를 사용'

# 실제 bootstrap의 로컬 파일 생성 구간만 실행해 시스템 설치는 호출하지 않는다.
awk '/^# 2. 로컬 환경변수 파일 생성/{capture=1} /^# 3. Infracost 설정/{capture=0} capture' "$ROOT/bootstrap.sh" >"$TMP/create-local.sh"
(
  umask 022
  HOME="$TMP/home" bash "$TMP/create-local.sh" >/dev/null
)
[ "$(stat -c %a "$TMP/home/.zshrc.local")" = 600 ]
printf '# preserve\n' >"$TMP/home/.zshrc.local"
chmod 644 "$TMP/home/.zshrc.local"
HOME="$TMP/home" bash "$TMP/create-local.sh" >/dev/null
[ "$(stat -c %a "$TMP/home/.zshrc.local")" = 600 ]
grep -qx '# preserve' "$TMP/home/.zshrc.local"
echo 'PASS: 신규·기존 로컬 파일 권한 0600 및 내용 보존'

mkdir "$TMP/repo"
git -C "$TMP/repo" init -q
for file in .terraform.lock.hcl AGENTS.md CLAUDE.md .claude/settings.json .agents/skills/demo/SKILL.md; do
  if git -C "$TMP/repo" -c core.excludesFile="$ROOT/stow/git/.gitignore_global" check-ignore --no-index -q "$file"; then
    echo "FAIL: 공유 파일이 숨겨짐: $file"
    exit 1
  fi
done
for file in .env .claude/settings.local.json; do
  git -C "$TMP/repo" -c core.excludesFile="$ROOT/stow/git/.gitignore_global" check-ignore --no-index -q "$file"
done
echo 'PASS: 공유 설정과 로컬 시크릿 ignore 구분'

# 로컬 설정의 사용자 값이 전역 기본값보다 우선한다.
printf '[core]\n    editor = user-editor\n' >"$TMP/local-config"
sed "s#~/.gitconfig.local#$TMP/local-config#" "$ROOT/stow/git/.gitconfig" >"$TMP/gitconfig"
[ "$(git config --file "$TMP/gitconfig" --includes --get core.editor)" = user-editor ]
echo 'PASS: Git 로컬 오버라이드 우선순위'
