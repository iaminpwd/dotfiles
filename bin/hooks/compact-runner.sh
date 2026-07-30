#!/usr/bin/env bash
# compact-runner.sh
# 범용 환경에서 토큰 절약을 위해 텍스트 출력을 컴팩트하게 변환하는 검증 래퍼 스크립트
#
# 합격/불합격은 래핑 대상 스크립트의 "종료 코드(exit code)"로만 판정 (거짓 통과 방지)
#
# 항목별 전체 결과를 보여주기 위해 개별 실패 시에도 남은 검증을 계속 진행

set -euo pipefail

# 이 스크립트가 실행된 현재 저장소의 루트를 찾음
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

# 검증할 스크립트 목록 수집
SCRIPTS=()

# --pfc-args=<값>: pre-flight-check.sh로 전달되는 패스스루 인자 (다중 지정 가능)
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
  if command -v pre-flight-check.sh >/dev/null 2>&1; then
    SCRIPTS+=("pre-flight-check.sh")
  fi

  # 2. dotfiles 저장소인 경우 예외적으로 prompt-lint.sh 추가
  if [ "$(basename "$REPO_ROOT")" = "dotfiles" ]; then
    if command -v prompt-lint.sh >/dev/null 2>&1; then
      SCRIPTS+=("prompt-lint.sh")
    fi
  fi

  # 3. 현재 저장소 내부의 모든 tests/run.sh 추가
  while IFS= read -r -d '' script; do
    SCRIPTS+=("$script")
  done < <(find "$REPO_ROOT" -name "run.sh" -path "*/tests/run.sh" -print0 2>/dev/null | sort -z || true)
fi

# 대상 스크립트가 없으면 무검증 통과 방지를 위해 명시적으로 경고 후 중단(exit 1)
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
  if [ -f "$script" ]; then
    CMD=(bash "$script")
  else
    CMD=("$script")
  fi

  if [[ "$script" == *"pre-flight-check.sh"* ]] && [ "${#PFC_ARGS[@]}" -gt 0 ]; then
    "${CMD[@]}" "${PFC_ARGS[@]}" >"$TMP_OUT" 2>&1 || rc=$?
  else
    "${CMD[@]}" >"$TMP_OUT" 2>&1 || rc=$?
  fi

  if [ "$rc" -eq 0 ]; then
    # 통과: 경고(WARNING/도구 미설치 등)만 남기고 나머지 정상/통계 로그는 억제
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
