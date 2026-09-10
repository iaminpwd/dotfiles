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
