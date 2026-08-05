#!/usr/bin/env bash
# test-yaml.sh
#
# validate_yaml(bin/lib/pfc-quality-checks.sh, pre-flight-check.sh가 source)는
# 이전까지 어떤 fixture 테스트도 없었다.
#
# 이 스위트는 두 층을 나눠서 본다.
#   1. CLI 레벨: validate_yaml 이 쓰는 것과 동일한 옵션(relaxed + line-length
#      disable)으로 yamllint 를 직접 호출해 판정 로직이 맞는지 확인한다.
#   2. 오케스트레이션 레벨: pre-flight-check.sh 자체를 격리 저장소에서 실제로
#      호출해 templates/ 하위 제외 로직(Helm Go 템플릿 문법 회피)이 실제로
#      동작하는지 확인한다. 같은 깨진 내용을 templates/ 안팎에 각각 둬서,
#      "yamllint가 이 내용을 원래 봐준다"가 아니라 "경로 때문에 건너뛴다"임을
#      증명한다(templates/ 밖에 두면 동일 내용이 실제로 커밋을 막는다).
#
# 사용: bash ~/dotfiles/contexts/pre-flight-check/tests/test-yaml.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
FIXTURES="$TESTS_DIR/fixtures-yaml"
PFC="$REPO_ROOT/bin/hooks/pre-flight-check.sh"

PASS_COUNT=0
FAIL_COUNT=0

require_tool() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "  FAIL  도구 미설치: $1 — 'mise install $1' 후 다시 실행하십시오"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  return 1
}

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

echo "=== validate_yaml 회귀 테스트 (pre-flight-check.sh) ==="

echo "--- yamllint -d relaxed (line-length disable) ---"
if require_tool yamllint; then
  status=0
  yamllint -d "{extends: relaxed, rules: {line-length: disable}}" "$FIXTURES/ok-baseline.yaml" >/dev/null 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then report "ok-baseline.yaml (지적 0건)" 0; else report "ok-baseline.yaml (지적 0건)" 1 "기대 exit=0 / 실제 exit=$status"; fi

  status=0
  out=$(yamllint -d "{extends: relaxed, rules: {line-length: disable}}" "$FIXTURES/fail-yamllint.yaml" 2>&1) || status=$?
  if [ "$status" -ne 0 ] && grep -qF "syntax error" <<<"$out"; then
    report "fail-yamllint.yaml (탭 들여쓰기 구문 오류 검출)" 0
  else
    report "fail-yamllint.yaml (탭 들여쓰기 구문 오류 검출)" 1 "기대 exit≠0 + syntax error / 실제 exit=$status"
  fi
fi

echo "--- pre-flight-check.sh (bin/hooks, 커밋 시점 배선) ---"
# 위 CLI 레벨 섹션은 "판정 로직이 맞는가"만 본다. validate_yaml의 templates/ 제외
# 오케스트레이션은 여기서 pre-flight-check.sh를 실제로 bash 호출해 검증한다
# (k8s-check.sh 등과 동일한 패턴으로 격리 저장소에서 실제 호출까지 확인).
if [ -x "$PFC" ] && require_tool yamllint; then
  PLUGIN_TMP=$(mktemp -d)

  run_pfc() {
    local repo=$1 status=0
    (cd "$repo" && QUIET=0 bash "$PFC") >"$PLUGIN_TMP/out" 2>&1 || status=$?
    echo "$status"
  }

  new_repo() {
    local root=$1
    mkdir -p "$root"
    git -C "$root" init -q
    git -C "$root" config user.email test@example.com
    git -C "$root" config user.name Test
  }

  # Case 1: templates/ 하위는 동일한 깨진 내용이라도 건너뛰어야 한다.
  YR1="$PLUGIN_TMP/repo1"
  new_repo "$YR1"
  mkdir -p "$YR1/chart/templates"
  cp "$FIXTURES/fail-yamllint.yaml" "$YR1/chart/templates/broken.yaml"
  git -C "$YR1" add chart/templates/broken.yaml
  status=$(run_pfc "$YR1")
  if [ "$status" -eq 0 ]; then
    report "templates-path-excluded (Go 템플릿 경로는 yamllint 건너뜀 -> 통과)" 0
  else
    report "templates-path-excluded (Go 템플릿 경로는 yamllint 건너뜀 -> 통과)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
  fi

  # Case 2: 같은 내용이라도 templates/ 밖이면 실제로 잡아야 한다 (제외가 "내용을
  # 봐주는 것"이 아니라 "경로 때문"임을 증명).
  YR2="$PLUGIN_TMP/repo2"
  new_repo "$YR2"
  mkdir -p "$YR2/chart"
  cp "$FIXTURES/fail-yamllint.yaml" "$YR2/chart/values.yaml"
  git -C "$YR2" add chart/values.yaml
  status=$(run_pfc "$YR2")
  if [ "$status" -eq 1 ] && grep -qF "yamllint 지적 사항이 발견되어 커밋이 중단되었습니다" "$PLUGIN_TMP/out"; then
    report "non-templates-path-blocked (같은 내용, templates/ 밖 -> 차단)" 0
  else
    report "non-templates-path-blocked (같은 내용, templates/ 밖 -> 차단)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
  fi

  rm -rf "$PLUGIN_TMP"
else
  report "pre-flight-check.sh 배선 확인" 1 "bin/hooks/pre-flight-check.sh 를 찾을 수 없거나 실행 권한이 없습니다"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
