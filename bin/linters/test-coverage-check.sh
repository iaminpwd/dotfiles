#!/usr/bin/env bash
# test-coverage-check.sh - bin/, git 훅, CI 스크립트의 회귀 테스트 커버리지 게이트
#
# 정적분석 도구(shellcheck/shfmt)는 문법·포맷 결함만 잡고, 검사 스크립트의 판정 로직(오탐/누락)
# 자체가 깨져도 조용히 통과한다. 이를 막기 위해 bin/{hooks,linters,utils,lib}, git/.githooks,
# .github/scripts 하위 모든 스크립트가 contexts/*/tests 어딘가에서 최소 1번은 참조되는지
# (=회귀 테스트 대상인지)만 기계적으로 확인한다. 실제 판정 로직의 정오는 각 test-*.sh 픽스처가
# 담당하고, 이 스크립트는 "테스트가 존재하는가"만 게이트한다.
#
# 여기에 더해 "그 테스트가 실제로 실행되는가"까지 게이트한다. 존재하는데 스킬의 run.sh 목록에
# 등록되지 않으면 결과는 테스트가 아예 없는 것과 같기 때문이다(아래 두 번째 하드 게이트 참조).
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
# .github/scripts/*.sh 도 같은 게이트 대상이다. ci.yml 이 "로컬 훅은 --no-verify 로 우회
# 가능하므로 이 job 이 실제 우회 불가능한 최종 게이트"라고 선언한 그 검증 로직이 여기 있는데,
# 정작 이 디렉토리만 커버리지 요구 밖이라 회귀 테스트가 하나도 없었다. 그 사각지대에서
# lint-commit-messages.sh 의 머지 판정 결함(조상에 머지가 있으면 모든 커밋이 면제되어
# 게이트가 통째로 무력화)이 실제로 살아 있었다.
CI_SCRIPTS_DIR="$REPO_ROOT/.github/scripts"
SELF="$(basename "${BASH_SOURCE[0]}")"

# SKILL.md/references 등 "문서상 언급"은 실제 테스트가 아니므로, tests/ 디렉토리로만 한정한다.
# 점으로 시작하는 컨텍스트 디렉토리(.shared)는 글롭이 dotglob 없이 건너뛰므로 별도 제외가 없다.
TEST_DIRS=()
for d in "$REPO_ROOT"/contexts/*/tests; do
  [ -d "$d" ] || continue
  TEST_DIRS+=("$d")
done

log_info "--- Step: Test Coverage Gate (bin/*.sh, git/.githooks/*, .github/scripts/*.sh) ---"

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
    # CI 게이트 스크립트(위 CI_SCRIPTS_DIR 주석 참조).
    find "$CI_SCRIPTS_DIR" -type f -name "*.sh" -print0 2>/dev/null
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
# 회귀 스위트 등록 누락 하드 게이트
# -----------------------------------------------------------------------------
# 위 게이트는 "테스트가 존재하는가"만 본다. 하지만 테스트 파일이 있어도 그 스킬의 run.sh
# 목록에 등록되지 않으면 just test / pre-push / CI 어디서도 실행되지 않고, 결과는 테스트가
# 아예 없는 것과 똑같다 — 판정 로직이 깨져도 아무것도 잡지 못하는 무검증 초록불.
# 실제로 test-pre-flight-live-hook.sh / test-pre-flight-gate-hook.sh 두 스위트(서브테스트
# 14건)가 등록 누락 상태로 한 번도 실행되지 않았는데, 파일 이름이 tests/ 안에 있다는 이유만으로
# 위 게이트는 통과였다. 즉 커버리지 게이트가 보증한 범위가 사실과 달랐다.
#
# 파일 패턴에 언더스코어(test_*.sh)를 함께 넣는 이유: 이 저장소에는
# contexts/prompt-architect/tests/test_prompt_lint.sh 처럼 언더스코어로 명명된 스위트가 실재한다.
# test-*.sh 로만 좁히면 그 파일이 이 게이트의 시야 밖으로 빠져, 지금 막으려는 것과 정확히 같은
# 클래스의 사각지대를 새로 만들게 된다.
#
# 위 첫 게이트와 달리 "주석에 언급됐는가"는 통과 근거로 치지 않는다. 등록이란 실행 목록에
# 들어갔다는 뜻인데, run.sh 주석에 이름이 스쳐 지나가도 통과시키면 그 순간 게이트가 무력화된다
# (실측: 이 게이트를 처음 넣은 직후, 같은 이름을 언급하는 설명 주석을 run.sh 에 추가했더니
# 등록을 실제로 빼도 통과해 버렸다). 그래서 주석 줄을 걷어낸 본문만 대조한다.
UNREGISTERED=()
MISSING_RUNNERS=()
for tdir in "${TEST_DIRS[@]}"; do
  runner="$tdir/run.sh"
  runner_code=""
  if [ -f "$runner" ]; then
    runner_code=$(grep -v '^[[:space:]]*#' "$runner" || true)
  fi
  while IFS= read -r -d '' tfile; do
    if [ ! -f "$runner" ]; then
      MISSING_RUNNERS+=("${tdir#"$REPO_ROOT"/}")
      break
    fi
    tname="$(basename "$tfile" .sh)"
    # here-string 을 쓴다. `grep -v ... | grep -qF ...` 형태는 오른쪽 grep 이 첫 매치에서
    # stdin 을 닫아 왼쪽이 SIGPIPE(141)로 끝나고, set -o pipefail 이 그것을 파이프라인
    # 결과로 채택해 "등록됐는데 미등록"으로 판정이 뒤집힌다(이 저장소의 tf_run_tflint /
    # check_documented_clause_existence 주석이 짚은 것과 동일한 함정).
    grep -qF -- "$tname" <<<"$runner_code" || UNREGISTERED+=("${tfile#"$REPO_ROOT"/}")
  done < <(find "$tdir" -maxdepth 1 -type f -name "test[-_]*.sh" -print0 2>/dev/null | sort -z)
done

if [ "${#UNREGISTERED[@]}" -gt 0 ] || [ "${#MISSING_RUNNERS[@]}" -gt 0 ]; then
  if [ "${#UNREGISTERED[@]}" -gt 0 ]; then
    echo "[ERROR] 아래 회귀 테스트는 파일은 있지만 같은 스킬의 tests/run.sh 목록에 등록되지 않아, just test/pre-push/CI 어디서도 실행되지 않습니다:" >&2
    for f in "${UNREGISTERED[@]}"; do
      echo "  - $f" >&2
    done
    echo "  -> 해당 run.sh 의 스위트 목록에 파일명(확장자 제외)을 추가하십시오." >&2
  fi
  if [ "${#MISSING_RUNNERS[@]}" -gt 0 ]; then
    echo "[ERROR] 아래 tests/ 디렉토리에는 회귀 테스트가 있는데 진입점(run.sh)이 없어 스위트가 통째로 실행되지 않습니다:" >&2
    for f in "${MISSING_RUNNERS[@]}"; do
      echo "  - $f" >&2
    done
    echo "  -> contexts/<skill>/tests/run.sh 를 추가해 각 테스트를 호출하십시오." >&2
  fi
  exit 1
fi

# -----------------------------------------------------------------------------
# SKIP 안내 가시성 하드 게이트
# -----------------------------------------------------------------------------
# 위 두 게이트는 "테스트가 존재하는가"와 "실행 목록에 등록됐는가"를 본다. 그런데 등록된
# 테스트가 실제로 돌았는지는 또 다른 문제다 — 도구가 없어 케이스를 건너뛰면 스위트는
# 그대로 exit 0 이고, run-suite.sh 는 통과한 스크립트의 출력에서 [WARNING]/⚠ 로 시작하는
# 줄만 남기고 나머지를 버린다. 그래서 "  SKIP ..." 형태의 안내는 just verify·CI·pre-push·
# Stop 게이트 훅 어디에서도 보이지 않고, 화면에는 "-> [✓]" 한 줄만 남는다.
#
# 실측: trufflehog 가 없는 환경에서 test-pre-commit-hook.sh 를 run-suite 로 감쌌더니
# 시크릿 스캔 회귀 2건(인덱스 내용 기준 스캔 / git mv 한 파일 스캔)이 통째로 건너뛰어졌는데
# 출력은 "-> [✓]" 뿐이었다. 하필 사라지는 것이 보안 축이라 대가가 크다.
#
# 규약 자체는 bin/lib/tool-probe.sh 의 print_unavailable_tools 와 bin/linters/prompt-lint.sh
# 헤더의 [출력 규약]이 이미 못 박아 뒀다("새 경고를 추가할 때 이 규약을 따를 것"). 문서
# 규칙으로만 두면 새 SKIP 이 추가될 때마다 조용히 낡으므로 여기서 기계적으로 대조한다.
#
# [주의] 출력 방식을 echo 하나로 좁히면 안 된다. run-suite.sh 의 압축 필터는 "출력 문자열"만
# 보므로, printf 로 찍든 홑따옴표를 쓰든 결과는 똑같이 버려진다 — 즉 게이트가 막으려는 상태를
# 흔한 표기 두 가지로 그대로 만들 수 있다(실측: printf "  SKIP ..." 과 echo '  SKIP ...' 이
# 동일한 출력을 내는데 echo+겹따옴표만 보던 판정은 둘 다 통과시켰다). 이 저장소는 실제로
# printf 와 홑따옴표를 곳곳에서 쓴다. 두 출력 명령과 두 따옴표를 모두 받는다.
#
# [한계] 문자열 리터럴 안의 SKIP 만 본다. `printf '  %s ...' "SKIP"` 처럼 인자로 조립하는
# 형태는 잡지 못하는데, 그 형태는 이 게이트의 회귀 테스트가 자기 픽스처를 스스로 신고하지
# 않으려고 의도적으로 쓰는 관용구이기도 하다(test-test-coverage-check.sh 참조).
#
# 판정은 오탐 0을 우선해 좁게 잡는다: 줄이 출력 명령으로 시작하고, 출력 문자열이 SKIP 으로
# 시작하는 경우만 본다. 주석에 SKIP 이 스쳐 지나가는 줄(스위트 헤더의 "도구 미설치는
# SKIP 이 아니라 실패로 처리한다" 등)은 구조적으로 배제된다.
SKIP_NO_PREFIX=()
while IFS= read -r -d '' tfile; do
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    SKIP_NO_PREFIX+=("${tfile#"$REPO_ROOT"/}:${hit%%:*}")
  done < <(grep -nE "^[[:space:]]*(echo|printf)[[:space:]]+['\"][[:space:]]*SKIP" "$tfile" 2>/dev/null || true)
done < <(find "$REPO_ROOT/contexts" -path "$REPO_ROOT/contexts/.*" -prune -o -path '*/tests/*' -name '*.sh' -print0 2>/dev/null)

if [ "${#SKIP_NO_PREFIX[@]}" -gt 0 ]; then
  echo "[ERROR] 아래 SKIP 안내는 run-suite.sh 의 압축 필터를 통과하지 못해, 도구 부재로 회귀가 건너뛰어져도 자동화 경로에서 보이지 않습니다:" >&2
  for f in "${SKIP_NO_PREFIX[@]}"; do
    echo "  - $f" >&2
  done
  echo "  -> 출력을 '[WARNING] SKIP ...' 으로 시작하십시오 (bin/lib/tool-probe.sh 의 print_unavailable_tools 와 동일한 규약)." >&2
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

log_info "[OK] bin/, git/.githooks/, .github/scripts/ 하위 모든 검사 스크립트가 최소 1개 이상의 회귀 테스트에서 참조되며, 모든 회귀 테스트가 스킬 run.sh에 등록되어 실제로 실행됩니다."
exit 0
