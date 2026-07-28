#!/usr/bin/env bash
# compact-runner.sh
# 범용 환경에서 토큰 절약을 위해 텍스트 출력을 컴팩트하게 변환하는 검증 래퍼 스크립트

set -euo pipefail

# 이 스크립트가 실행된 현재 저장소의 루트를 찾음
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

# 검증할 스크립트 목록 수집
SCRIPTS=()

if [ $# -gt 0 ]; then
  # 인자가 주어지면 해당 스크립트들만 실행
  SCRIPTS=("$@")
else
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

for script in "${SCRIPTS[@]}"; do
  # 출력 가독성을 위해 절대 경로에서 REPO_ROOT 또는 HOME 경로를 제거
  SCRIPT_NAME="${script#"$REPO_ROOT"/}"
  SCRIPT_NAME="${SCRIPT_NAME#"$HOME"/}"

  # 스트림 파싱을 통해 출력을 실시간으로 압축
  bash "$script" 2>&1 | awk -v script_name="$SCRIPT_NAME" '
    BEGIN { pass_list = ""; has_error = 0; }
    
    /^[ \t]*PASS[ \t]+/ || /^\[INFO\]/ || /^\[SUCCESS\]/ {
      sub(/^[ \t]*PASS[ \t]+/, "", $0)
      sub(/^\[INFO\][ \t]+/, "", $0)
      sub(/^\[SUCCESS\][ \t]+/, "", $0)
      if (pass_list == "") { pass_list = $0 }
      else { pass_list = pass_list ", " $0 }
      next
    }

    # 불필요한 장황한 진행 로그 및 헤더 완전 숨김
    /^Checking / || /^Running / || /^Validating / || /^Linting / || /^---/ || /^===/ {
      next
    }
    
    # 빈 줄 및 통계 요약 텍스트 무시 (에러로 간주하지 않음)
    /^$/ || /^[0-9]+\/[0-9]+ 통과/ || /회귀 테스트 전체 통과/ {
      next
    }
    
    # 그 외 (에러나 일반 텍스트)
    {
      if (!has_error) {
        print "❌ [" script_name "] -----------------------------------------"
        has_error = 1
      }
      if (pass_list != "") {
        print "  (Passed so far: " pass_list ")"
        pass_list = ""
      }
      print $0
    }
    
    END {
      if (!has_error) {
        print "  -> [✓] " script_name
      } else {
        if (pass_list != "") {
          print "  (Passed at the end: " pass_list ")"
        }
        print "----------------------------------------------------------------"
      }
    }
  '
done
