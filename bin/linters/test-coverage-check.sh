#!/usr/bin/env bash
# test-coverage-check.sh - bin/ 및 git 훅 검사 스크립트의 회귀 테스트 커버리지 게이트
#
# 정적분석 도구(shellcheck/shfmt)는 문법·포맷 결함만 잡고, 검사 스크립트의 판정 로직(오탐/누락)
# 자체가 깨져도 조용히 통과한다. 이를 막기 위해 bin/{hooks,linters,utils,lib} 및 git/.githooks
# 하위 모든 스크립트가 contexts/*/tests 어딘가에서 최소 1번은 참조되는지(=회귀 테스트 대상인지)만
# 기계적으로 확인한다. 실제 판정 로직의 정오는 각 test-*.sh 픽스처가 담당하고, 이 스크립트는
# "테스트가 존재하는가"만 게이트한다.
#
# git/.githooks/*도 bin/*.sh와 동일하게 스캔한다. 훅 파일명은 git 컨벤션상 확장자가 없어
# (pre-commit/pre-push/commit-msg) "*.sh"로는 걸러지지 않으므로 별도로 전부 스캔한다.

set -euo pipefail

# lib/ 경로를 리터럴로 분리하여 shellcheck SC1091 오류 회피 (심볼릭 링크 호출 호환성 보장)
TCC_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source-path=SCRIPTDIR
source "$TCC_SCRIPT_DIR/../lib/script-init.sh"

# 이 스크립트는 pre-flight-check.sh처럼 "호출 시점의 현재 저장소"를 검증하는 범용
# 도구가 아니라 항상 자기 자신이 속한 dotfiles 저장소만 대상으로 하는 전용 게이트다.
# init_repo_root()의 git rev-parse --show-toplevel(호출 CWD 기준)을 쓰면 dotfiles 밖에서
# 호출됐을 때 REPO_ROOT가 엉뚱한 곳을 가리켜 find(BIN_DIR)가 조용히 빈 결과를 내고
# (프로세스 치환 안이라 set -e가 못 잡음) "커버리지 0건 = 통과"라는 거짓 그린라이트가
# 뜬다. CWD와 무관하게 스크립트 자신의 물리적 위치로 REPO_ROOT를 고정한다
# (generate-context-index.sh와 동일 패턴).
REPO_ROOT=$(cd "$TCC_SCRIPT_DIR/../.." && pwd)

BIN_DIR="$REPO_ROOT/bin"
HOOKS_DIR="$REPO_ROOT/stow/git/.githooks"
SELF="$(basename "${BASH_SOURCE[0]}")"

# contexts/.archive 는 사용 종료된 스킬이라 커버리지 요구 대상에서 제외.
# SKILL.md/references 등 "문서상 언급"은 실제 테스트가 아니므로, tests/ 디렉토리로만 한정한다.
TEST_DIRS=()
for d in "$REPO_ROOT"/contexts/*/tests; do
  [ -d "$d" ] || continue
  case "$d" in "$REPO_ROOT/contexts/.archive/"*) continue ;; esac
  TEST_DIRS+=("$d")
done

log_info "--- Step: Test Coverage Gate (bin/*.sh, git/.githooks/*) ---"

UNTESTED=()
while IFS= read -r -d '' script; do
  name="$(basename "$script")"
  [ "$name" = "$SELF" ] && continue

  # --binary-files=without-match: infracost 픽스처 등 바이너리 파일 내 우발적 매치 방지
  if ! grep -qrlF --binary-files=without-match -- "$name" "${TEST_DIRS[@]}" 2>/dev/null; then
    UNTESTED+=("${script#"$REPO_ROOT"/}")
  fi
done < <(
  {
    find "$BIN_DIR" -type f -name "*.sh" -print0
    # git 훅은 확장자가 없는 고정 파일명(pre-commit/pre-push/commit-msg)이라 "*.sh"로
    # 걸러지지 않으므로 별도로 전부 스캔한다.
    find "$HOOKS_DIR" -type f -print0 2>/dev/null
  } | sort -z
)

if [ "${#UNTESTED[@]}" -gt 0 ]; then
  echo "[ERROR] 아래 검사 스크립트는 contexts/*/tests 어디에서도 참조되지 않아, 로직이 깨져도 아무 테스트가 잡지 못합니다:" >&2
  for f in "${UNTESTED[@]}"; do
    echo "  - $f" >&2
  done
  echo "  -> contexts/<skill>/tests/test-<name>.sh 를 추가하고 해당 스킬의 run.sh에 등록하십시오." >&2
  exit 1
fi

# -----------------------------------------------------------------------------
# Plugin 전용 강화 검사 (경고 전용, 하드 블록 아님)
# -----------------------------------------------------------------------------
# bin/hooks/plugins/*.sh는 위 하드 게이트("이름이 어딘가 언급됐는가")만으로는 부족하다.
# 이름이 테스트의 주석·echo 라벨에만 등장해도 하드 게이트는 통과하지만, 파일을 bash로
# 실제 호출하는 코드는 없을 수 있다. 그런 사각지대를 잡기 위해 "실제 bash 호출 증거"까지
# 요구하는 검사를 추가한다. 기존 플러그인을 강제로 뜯어고치게 만들지 않도록 하드
# 블록이 아니라 경고로만 남긴다.
PLUGINS_DIR="$BIN_DIR/hooks/plugins"
WEAK_COVERAGE=()
if [ -d "$PLUGINS_DIR" ]; then
  while IFS= read -r -d '' plugin; do
    pname="$(basename "$plugin")"
    pname_esc="${pname//./\\.}"
    invoked=0
    for tdir in "${TEST_DIRS[@]}"; do
      while IFS= read -r -d '' tfile; do
        # 패턴 A: 직접 인라인 호출 -> bash "...<plugin>.sh"
        if grep -qE "bash[[:space:]]+\"[^\"]*${pname_esc}\"" "$tfile" 2>/dev/null; then
          invoked=1
          break
        fi
        # 패턴 B: 변수 대입 후 bash "$VAR"/"${VAR}" 호출 (이 저장소 테스트들의 표준 관례).
        # 대입문이 if/for 블록 안에 들여쓰기돼 있는 경우가 있어 줄 앞 공백을 허용한다.
        while IFS= read -r varname; do
          [ -n "$varname" ] || continue
          if grep -qE "bash[[:space:]]+\"\\\$\{?${varname}\}?\"" "$tfile" 2>/dev/null; then
            invoked=1
            break
          fi
        done < <(grep -oE "^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=.*${pname_esc}\"?\$" "$tfile" 2>/dev/null | sed -E 's/^[[:space:]]*//; s/=.*//')
        [ "$invoked" -eq 1 ] && break
      done < <(find "$tdir" -type f -name "*.sh" -print0 2>/dev/null)
      [ "$invoked" -eq 1 ] && break
    done
    [ "$invoked" -eq 0 ] && WEAK_COVERAGE+=("bin/hooks/plugins/$pname")
  done < <(find "$PLUGINS_DIR" -maxdepth 1 -type f -name "*.sh" -print0)
fi

if [ "${#WEAK_COVERAGE[@]}" -gt 0 ]; then
  echo "[WARNING] 아래 플러그인은 이름이 회귀 테스트에 언급되긴 하지만(위 하드 게이트는 통과), 실제로 bash로 호출되는 테스트 증거를 찾지 못했습니다. 트리거/차단/통과 시나리오를 직접 실행해 검증하는 테스트를 추가하는 것을 권장합니다:" >&2
  for f in "${WEAK_COVERAGE[@]}"; do
    echo "  - $f" >&2
  done
fi

log_info "[OK] bin/ 및 git/.githooks/ 하위 모든 검사 스크립트가 최소 1개 이상의 회귀 테스트에서 참조됩니다."
exit 0
