#!/usr/bin/env bash
# test-plugin-targets.sh
#
# bin/lib/plugin-targets.sh 는 위임 플러그인 3개(k8s/observability/aiops)가 공유하는
# "검사 대상 수집" SSOT다. 이 계약이 깨지면 예전처럼 플러그인이 실행 모드를 무시하고
# 항상 스테이징만 보게 되어, --all(just verify/CI)과 explicit(pre-flight-live-hook.sh)
# 경로에서 위임 검증이 통째로 비면서 초록불만 뜬다(실측 재현된 버그, 라이브러리 헤더 참조).
# 그 무검증 통과가 재발하지 않도록 아래 4개 계약을 고정한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-plugin-targets.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
LIB="$REPO_ROOT/bin/lib/plugin-targets.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

report() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" -eq 0 ]; then
    echo "  PASS  $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL  $name"
    [ -n "$detail" ] && echo "        $detail"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo "--- plugin-targets.sh 공용 라이브러리 (SSOT) ---"

# 1. 라이브러리 계약: source 하면 plugin_target_files 함수가 정의되어야 한다.
code=0
bash -c 'set -euo pipefail
  source "$1"
  declare -F plugin_target_files >/dev/null' _ "$LIB" || code=$?
if [ "$code" -eq 0 ]; then
  report "plugin_target_files 함수 제공" 0
else
  report "plugin_target_files 함수 제공" 1 "exit=$code"
fi

# 2. 인자 목록이 주어지면 그 목록에서 패턴에 맞는 것만 골라낸다(스테이징과 무관).
#    이게 깨지면 --all/explicit 모드가 다시 스테이징만 보게 된다.
OUT=$(bash -c 'set -euo pipefail
  source "$1"
  PLUGIN_TARGET_FILES=(a.yaml b.json c.tf d.md e.yml)
  plugin_target_files "*.yaml" "*.yml" | tr "\0" " "' _ "$LIB")
if [ "$OUT" = "a.yaml e.yml " ]; then
  report "인자 목록을 패턴으로 필터링" 0
else
  report "인자 목록을 패턴으로 필터링" 1 "기대='a.yaml e.yml ' 실제='$OUT'"
fi

# 3. 한 파일이 여러 패턴에 걸려도 중복 출력하지 않는다(플러그인이 같은 파일을 두 번 검사하면
#    동일 위반이 두 번 보고돼 노이즈가 된다).
OUT=$(bash -c 'set -euo pipefail
  source "$1"
  PLUGIN_TARGET_FILES=(x.yaml)
  plugin_target_files "*.yaml" "*.yaml" "x.*" | tr "\0" " "' _ "$LIB")
if [ "$OUT" = "x.yaml " ]; then
  report "다중 패턴 매치 시 중복 출력 없음" 0
else
  report "다중 패턴 매치 시 중복 출력 없음" 1 "기대='x.yaml ' 실제='$OUT'"
fi

# 4. 인자가 없으면 스테이징 기준으로 폴백한다. 각 스킬의 회귀 테스트와 수동 실행이
#    플러그인을 인자 없이 직접 호출하므로, 이 폴백이 깨지면 그 호출 계약이 모두 깨진다.
FALLBACK_REPO="$TMP/fallback"
mkdir -p "$FALLBACK_REPO"
git -C "$FALLBACK_REPO" init -q
printf 'kind: Foo\n' >"$FALLBACK_REPO/staged.yaml"
printf 'kind: Bar\n' >"$FALLBACK_REPO/untracked.yaml"
git -C "$FALLBACK_REPO" add staged.yaml

OUT=$(cd "$FALLBACK_REPO" && bash -c 'set -euo pipefail
  source "$1"
  GLOBAL_IS_GIT_REPO=1
  plugin_target_files "*.yaml" | tr "\0" " "' _ "$LIB")
if [ "$OUT" = "staged.yaml " ]; then
  report "인자 없으면 스테이징 기준으로 폴백" 0
else
  report "인자 없으면 스테이징 기준으로 폴백" 1 "기대='staged.yaml ' 실제='$OUT'"
fi

# 5. git 저장소가 아니면 폴백은 조용히 빈 결과를 낸다(에러로 죽지 않아야 훅이 fail-open 유지).
OUT=$(cd "$TMP" && bash -c 'set -euo pipefail
  source "$1"
  GLOBAL_IS_GIT_REPO=0
  plugin_target_files "*.yaml" | tr "\0" " "' _ "$LIB")
if [ -z "$OUT" ]; then
  report "비-git 환경에서 빈 결과로 안전 종료" 0
else
  report "비-git 환경에서 빈 결과로 안전 종료" 1 "실제='$OUT'"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
