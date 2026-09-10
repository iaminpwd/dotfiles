#!/usr/bin/env bash
# test-coverage-check.sh - 회귀 테스트 등록 및 SKIP 안내 검사
# 기존 훅/CLI 호환을 위해 이름은 유지한다. 파일명 언급이나 bash 호출 패턴으로
# 테스트 커버리지를 추정하지 않으며, 실제 동작은 회귀 테스트 실행으로 검증한다.

set -euo pipefail

TCC_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source-path=SCRIPTDIR
source "$TCC_SCRIPT_DIR/../lib/script-init.sh"

# CWD와 무관하게 이 스크립트가 속한 저장소만 검사한다.
REPO_ROOT=$(cd "$TCC_SCRIPT_DIR/../.." && pwd)

# 숨김 스킬(.shared 등)은 런타임/테스트 목록에서 제외한다.
TEST_DIRS=()
for d in "$REPO_ROOT"/contexts/*/tests; do
  [ -d "$d" ] || continue
  TEST_DIRS+=("$d")
done

log_info "--- Step: Test Registration and SKIP Visibility ---"

# 명시적 스위트 목록을 사용하는 현재 tests/run.sh 관례의 등록 누락을 검사한다.
# 이름 일치는 정적 검사이며 실제 실행이나 커버리지를 보증하지 않는다.
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

# run-suite.sh가 보존하는 경고 접두사 없이 SKIP 안내를 출력하면 결과가 숨겨진다.
# echo/printf 문자열 리터럴만 검사하며 동적으로 조립된 출력은 실행 테스트로 확인한다.
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

log_info "[OK] 회귀 테스트 등록과 SKIP 안내 정적 검사 통과. 실제 실행 결과는 각 테스트 스위트에서 확인하십시오."
exit 0
