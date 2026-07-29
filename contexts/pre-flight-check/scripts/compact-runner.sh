#!/usr/bin/env bash
# compact-runner.sh
# 범용 환경에서 토큰 절약을 위해 텍스트 출력을 컴팩트하게 변환하는 검증 래퍼 스크립트
#
# 합격/불합격은 래핑한 스크립트의 "종료 코드"로만 판정한다. 예전에는 stdout 패턴으로
# 판정해서, 출력이 전부 무시 패턴(PASS / "N/N 통과" / 구분선)에만 걸리는 실패 스크립트를
# `-> [✓]` 로 표시했다(2026-07-28 실측: exit 1 인데 통과 표시). 이 래퍼의 출력을 읽는
# 주체가 사람과 AI 에이전트이므로, 거짓 초록불은 검증 게이트를 통째로 무력화한다.
#
# 실패해도 남은 스크립트를 계속 실행한다. 예전에는 set -e 가 루프를 즉시 죽여서, 인자
# 없이 실행하는 기본 경로에서 첫 스크립트가 실패하면 prompt-lint 와 테스트 스위트가
# 아무 안내 없이 통째로 건너뛰어졌다(2026-07-28 실측). 검증 게이트는 어느 항목이
# 실패했는지 전부 보여준 뒤 마지막에 한 번 중단해야 한다.

set -euo pipefail

# 이 스크립트가 실행된 현재 저장소의 루트를 찾음
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

# 검증할 스크립트 목록 수집
SCRIPTS=()

# --pfc-args=<값> 은 pre-flight-check.sh 한 곳으로만 전달되는 패스스루 인자다. 값 하나가
# 인자 하나로 그대로 전달되므로(단어 분리 없음), 공백이 든 경로도 안전하다. 대상이 여러
# 개면 --pfc-args= 를 여러 번 쓴다.
PFC_ARGS=()

for arg in "$@"; do
  if [[ "$arg" == --pfc-args=* ]]; then
    PFC_ARGS+=("${arg#--pfc-args=}")
  else
    SCRIPTS+=("$arg")
  fi
done

if [ "${#SCRIPTS[@]}" -eq 0 ]; then
  # 인자가 없으면 디폴트로 저장소 내 모든 테스트 및 pre-flight 스캔 수집
  # 1. 공통 필수: pre-flight-check.sh (어느 환경에서든 실행)
  PRE_FLIGHT_PATH="$HOME/dotfiles/contexts/pre-flight-check/scripts/pre-flight-check.sh"
  if [ -f "$PRE_FLIGHT_PATH" ]; then
    SCRIPTS+=("$PRE_FLIGHT_PATH")
  fi

  # 2. dotfiles 저장소인 경우 예외적으로 prompt-lint.sh 추가
  if [ "$(basename "$REPO_ROOT")" = "dotfiles" ]; then
    PROMPT_LINT="$REPO_ROOT/contexts/dotfiles/scripts/prompt-lint.sh"
    if [ -f "$PROMPT_LINT" ]; then
      SCRIPTS+=("$PROMPT_LINT")
    fi
  fi

  # 3. 현재 저장소 내부의 모든 tests/run.sh 추가
  while IFS= read -r -d '' script; do
    SCRIPTS+=("$script")
  done < <(find "$REPO_ROOT" -name "run.sh" -path "*/tests/run.sh" -print0 2>/dev/null | sort -z || true)
fi

# 실행할 대상이 하나도 없으면 조용히 exit 0 하지 않는다. 검증을 "전부 통과"와 구분할 수
# 없는 무검증 통과가 되어, 이 래퍼가 막으려는 가짜 초록불이 그대로 재현된다.
if [ "${#SCRIPTS[@]}" -eq 0 ]; then
  echo "[ERROR] 실행할 검증 스크립트를 찾지 못했습니다 (탐색 기준: $REPO_ROOT)." >&2
  exit 1
fi

TMP_OUT=$(mktemp)
trap 'rm -f "$TMP_OUT"' EXIT

FAILED=()

for script in "${SCRIPTS[@]}"; do
  # 출력 가독성을 위해 절대 경로에서 REPO_ROOT 또는 HOME 경로를 제거
  SCRIPT_NAME="${script#"$REPO_ROOT"/}"
  SCRIPT_NAME="${SCRIPT_NAME#"$HOME"/}"

  rc=0
  if [[ "$script" == *"pre-flight-check.sh"* ]] && [ "${#PFC_ARGS[@]}" -gt 0 ]; then
    bash "$script" "${PFC_ARGS[@]}" >"$TMP_OUT" 2>&1 || rc=$?
  else
    bash "$script" >"$TMP_OUT" 2>&1 || rc=$?
  fi

  if [ "$rc" -eq 0 ]; then
    # 통과: 정상 로그(PASS/INFO/SUCCESS/구분선/통계)는 접고 경고만 남긴다. 경고까지
    # 버리면 "도구 미설치로 검증을 건너뛰었다"는 신호가 사라져, pre-flight-check.sh 가
    # UNAVAILABLE_TOOLS 로 알리려는 가짜 초록불이 래퍼 단계에서 되살아난다.
    grep -aE '^[[:space:]]*(\[WARNING\]|⚠)' "$TMP_OUT" | sed 's/^[[:space:]]*/  /' || true
    printf '  -> [✓] %s\n' "$SCRIPT_NAME"
  else
    FAILED+=("$SCRIPT_NAME")
    # 실패 시에는 압축하지 않고 원형 로그를 그대로 보존한다(디버깅 추적성 확보).
    printf '❌ [%s] exit=%s ------------------------------------------\n' "$SCRIPT_NAME" "$rc"
    cat "$TMP_OUT"
    printf -- '----------------------------------------------------------------\n'
  fi
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  printf '❌ 검증 실패 %s/%s: %s\n' "${#FAILED[@]}" "${#SCRIPTS[@]}" "${FAILED[*]}" >&2
  exit 1
fi
