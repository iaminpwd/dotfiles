#!/usr/bin/env bash
# test-coverage-check.sh - 자동 탐색 실행 누락 및 SKIP 안내 검사
# 기존 훅/CLI 호환을 위해 이름은 유지한다. 파일명 언급이나 bash 호출 패턴으로
# 테스트 커버리지를 추정하지 않으며, 실제 동작은 회귀 테스트 실행으로 검증한다.

set -euo pipefail

# GNU readlink -f는 macOS 기본 BSD readlink에 없다. symlink/상대 경로를
# plain readlink + cd -P로 해석해 호출 CWD와 관계없이 정본 저장소를 찾는다.
tcc_canonical_path() {
  local path=$1 dir target
  while [ -L "$path" ]; do
    dir=$(cd -P "$(dirname "$path")" && pwd) || return 1
    target=$(readlink "$path") || return 1
    case "$target" in
    /*) path="$target" ;;
    *) path="$dir/$target" ;;
    esac
  done
  dir=$(cd -P "$(dirname "$path")" && pwd) || return 1
  printf '%s/%s\n' "$dir" "$(basename "$path")"
}

TCC_SCRIPT_PATH=$(tcc_canonical_path "${BASH_SOURCE[0]}")
TCC_SCRIPT_DIR=$(dirname "$TCC_SCRIPT_PATH")
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

# Test files are discovered dynamically by their domain runner, not listed
# manually. Exercise its read-only --list contract to catch a runner that
# silently omits an added test. The six fixture-driven domain runners without
# standalone test-*.sh files keep their existing interfaces.
MISSING_RUNNERS=()
DISCOVERY_MISMATCH=()
for tdir in "${TEST_DIRS[@]}"; do
  shopt -s nullglob
  candidates=("$tdir"/test-*.sh "$tdir"/test_*.sh)
  shopt -u nullglob
  [ "${#candidates[@]}" -gt 0 ] || continue
  runner="$tdir/run.sh"
  if [ ! -f "$runner" ]; then
    MISSING_RUNNERS+=("${tdir#"$REPO_ROOT"/}")
    continue
  fi
  expected=$(printf "%s\n" "${candidates[@]}")
  actual=$(bash "$runner" --list 2>/dev/null) || actual=""
  if [ "$actual" != "$expected" ]; then
    DISCOVERY_MISMATCH+=("${tdir#"$REPO_ROOT"/}")
  fi
done

if [ "${#MISSING_RUNNERS[@]}" -gt 0 ] || [ "${#DISCOVERY_MISMATCH[@]}" -gt 0 ]; then
  for d in "${MISSING_RUNNERS[@]}"; do
    echo "[ERROR] 회귀 테스트가 있지만 tests/run.sh 진입점이 없습니다: $d" >&2
  done
  for d in "${DISCOVERY_MISMATCH[@]}"; do
    echo "[ERROR] tests/run.sh --list가 실제 test[-_]*.sh 목록과 일치하지 않습니다: $d" >&2
  done
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
