#!/usr/bin/env bash
# test-coverage-check.sh - 회귀 테스트 등록 및 SKIP 안내 검사
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

# 명시적 스위트 목록을 사용하는 현재 tests/run.sh 관례의 등록 누락을 검사한다.
# 이름 일치는 정적 검사이며 실제 실행이나 커버리지를 보증하지 않는다.
UNREGISTERED=()
MISSING_RUNNERS=()
for tdir in "${TEST_DIRS[@]}"; do
  runner="$tdir/run.sh"
  registered_suites=""
  if [ -f "$runner" ]; then
    # for suite in ...; do 목록만 읽는다. 길어진 dotfiles 목록은 Bash의
    # backslash-newline 이어쓰기 한 줄에 테스트 하나씩 두며, 기존 한 줄 형식도 지원한다.
    # 주석/echo/dead branch에서 이름을 발견해도 등록으로 인정하지 않는다.
    # POSIX awk만 사용하여 macOS 기본 도구에서도 동일하게 검사한다.
    registered_suites=$(awk '
      /^[[:space:]]*for[[:space:]]+suite[[:space:]]+in[[:space:]]/ {
        statement = $0
        while (statement ~ /\\[[:space:]]*$/) {
          sub(/\\[[:space:]]*$/, "", statement)
          if ((getline continuation) <= 0) {
            statement = ""
            break
          }
          statement = statement " " continuation
        }
        if (statement ~ /^[[:space:]]*for[[:space:]]+suite[[:space:]]+in[[:space:]]+[^;]+;[[:space:]]*do[[:space:]]*$/) {
          sub(/^[[:space:]]*for[[:space:]]+suite[[:space:]]+in[[:space:]]+/, "", statement)
          sub(/;[[:space:]]*do[[:space:]]*$/, "", statement)
          print statement
        }
      }
    ' "$runner" | tr '\n' ' ')
  fi
  while IFS= read -r -d '' tfile; do
    if [ ! -f "$runner" ]; then
      MISSING_RUNNERS+=("${tdir#"$REPO_ROOT"/}")
      break
    fi
    tname="$(basename "$tfile" .sh)"
    registered=0
    for suite_name in $registered_suites; do
      if [ "$suite_name" = "$tname" ]; then
        registered=1
        break
      fi
    done
    [ "$registered" -eq 1 ] || UNREGISTERED+=("${tfile#"$REPO_ROOT"/}")
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
