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

# bootstrap 권한 선택: root / 일반 사용자+sudo / 일반 사용자+sudo 없음 세 경로를 고정한다.
ROOT_FN="$TMP/run-as-root.sh"
awk '/^run_as_root\(\) \{/{capture=1} capture{print} capture && /^}/{exit}' "$ROOT/bootstrap.sh" >"$ROOT_FN"
grep -q '^run_as_root()' "$ROOT_FN"
# shellcheck disable=SC1090
source "$ROOT_FN"

ROOT_MARKER="$TMP/root-path"
SUDO_MARKER="$TMP/sudo-path"
ROOT_BIN="$TMP/root-bin"
mkdir -p "$ROOT_BIN"
cat >"$ROOT_BIN/id" <<'STUB'
#!/bin/sh
printf '0\n'
STUB
cat >"$ROOT_BIN/sudo" <<'STUB'
#!/bin/sh
printf 'unexpected\n' >"$SUDO_MARKER"
exit 99
STUB
cat >"$ROOT_BIN/privcmd" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >"$ROOT_MARKER"
STUB
chmod +x "$ROOT_BIN/id" "$ROOT_BIN/sudo" "$ROOT_BIN/privcmd"
PATH="$ROOT_BIN" ROOT_MARKER="$ROOT_MARKER" SUDO_MARKER="$SUDO_MARKER" run_as_root privcmd direct-root
[ "$(cat "$ROOT_MARKER")" = "direct-root" ]
[ ! -e "$SUDO_MARKER" ]
echo 'PASS: root 사용자는 sudo 없이 직접 실행'

SUDO_BIN="$TMP/sudo-bin"
mkdir -p "$SUDO_BIN"
cat >"$SUDO_BIN/id" <<'STUB'
#!/bin/sh
printf '1000\n'
STUB
cat >"$SUDO_BIN/sudo" <<'STUB'
#!/bin/sh
printf 'used\n' >"$SUDO_MARKER"
exec "$@"
STUB
cp "$ROOT_BIN/privcmd" "$SUDO_BIN/privcmd"
chmod +x "$SUDO_BIN/id" "$SUDO_BIN/sudo" "$SUDO_BIN/privcmd"
PATH="$SUDO_BIN" ROOT_MARKER="$ROOT_MARKER" SUDO_MARKER="$SUDO_MARKER" run_as_root privcmd via-sudo
[ "$(cat "$ROOT_MARKER")" = "via-sudo" ]
[ "$(cat "$SUDO_MARKER")" = "used" ]
echo 'PASS: 일반 사용자는 sudo 경로 사용'

NO_SUDO_BIN="$TMP/no-sudo-bin"
mkdir -p "$NO_SUDO_BIN"
cp "$SUDO_BIN/id" "$SUDO_BIN/privcmd" "$NO_SUDO_BIN/"
status=0
out=$(PATH="$NO_SUDO_BIN" ROOT_MARKER="$ROOT_MARKER" run_as_root privcmd denied 2>&1) || status=$?
[ "$status" -ne 0 ]
grep -q 'sudo를 찾을 수 없습니다' <<<"$out"
echo 'PASS: 일반 사용자 + sudo 없음은 명확히 실패'

grep -q '^  run_as_root apt-get update -qq$' "$ROOT/bootstrap.sh"
grep -q '^  run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install ' "$ROOT/bootstrap.sh"
grep -q '^  run_as_root dnf install ' "$ROOT/bootstrap.sh"
if grep -Eq '^[[:space:]]*sudo (apt-get|dnf)' "$ROOT/bootstrap.sh"; then
  echo 'FAIL: bootstrap Linux 패키지 설치가 sudo를 직접 호출합니다.'
  exit 1
fi
echo 'PASS: apt/dnf bootstrap 호출부가 권한 wrapper를 사용'

if ! grep -Fq 'epel-release-latest-${os_major}.noarch.rpm' "$ROOT/bootstrap.sh"; then
  echo 'FAIL: bootstrap의 dnf 경로가 RHEL 메이저 버전별 EPEL release RPM을 직접 설치하지 않습니다.'
  exit 1
fi
if grep -Eq 'run_as_root dnf install -y epel-release([[:space:]]|$)' "$ROOT/bootstrap.sh"; then
  echo 'FAIL: bootstrap이 stock RHEL에서 제공되지 않을 수 있는 bare epel-release 패키지에 의존합니다.'
  exit 1
fi
echo 'PASS: RHEL bootstrap이 메이저 버전별 EPEL release RPM을 직접 사용'

EPEL_FN="$TMP/install-epel-release.sh"
awk '/^install_epel_release\(\) \{/{capture=1} capture{print} capture && /^}/{exit}' "$ROOT/bootstrap.sh" >"$EPEL_FN"
grep -q '^install_epel_release()' "$EPEL_FN"
# shellcheck disable=SC1090
source "$EPEL_FN"

EPEL_BIN="$TMP/epel-bin"
EPEL_MARKER="$TMP/epel-dnf-args"
mkdir -p "$EPEL_BIN"
cat >"$EPEL_BIN/id" <<'STUB'
#!/bin/sh
printf '0\n'
STUB
cat >"$EPEL_BIN/rpm" <<'STUB'
#!/bin/sh
if [ "$1" = "-E" ] && [ "$2" = "%{rhel}" ]; then
  printf '9\n'
  exit 0
fi
exit 1
STUB
cat >"$EPEL_BIN/dnf" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >"$EPEL_MARKER"
STUB
chmod +x "$EPEL_BIN/id" "$EPEL_BIN/rpm" "$EPEL_BIN/dnf"
PATH="$EPEL_BIN" EPEL_MARKER="$EPEL_MARKER" install_epel_release
grep -Fq 'https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm' "$EPEL_MARKER"
echo 'PASS: RHEL 9 판별 시 EPEL 9 release RPM URL을 dnf에 전달'

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
