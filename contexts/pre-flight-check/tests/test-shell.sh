#!/usr/bin/env bash
# test-shell.sh
#
# validate_shell(bin/lib/pfc-quality-checks.sh, pre-flight-check.sh가 source)는
# 이전까지 어떤 fixture 테스트도 없었다. shfmt/shellcheck/zsh -n 을 확장자별로
# 분기 호출하는 로직인데, 그 판정이 맞는지도, 분기 자체가 맞는지도 검증된 적이 없었다.
#
# 이 스위트는 두 층을 나눠서 본다.
#   1. CLI 레벨: validate_shell 이 쓰는 것과 동일한 명령·옵션으로 각 도구를 직접
#      호출해 판정 로직이 맞는지 확인한다(다른 스킬 스위트와 동일한 관용구).
#   2. 오케스트레이션 레벨: pre-flight-check.sh 자체를 격리 저장소에서 실제로
#      호출해 확장자별 분기(.zsh는 zsh -n만 받고 shfmt/shellcheck/bash -n을
#      받지 않는지, .sh 위반은 실제로 커밋을 막는지)를 확인한다. `repeat N; do`는
#      zsh 문법으로는 유효하지만 bash -n으로는 파스 에러다 — 이 파일이 통과한다는
#      것 자체가 bash 계열 도구가 적용되지 않았다는 증거다.
#
# 사용: bash ~/dotfiles/contexts/pre-flight-check/tests/test-shell.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
FIXTURES="$TESTS_DIR/fixtures-shell"
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

echo "=== validate_shell 회귀 테스트 (pre-flight-check.sh) ==="

echo "--- shfmt -d -i 2 ---"
if require_tool shfmt; then
  status=0
  shfmt -d -i 2 "$FIXTURES/ok-baseline.sh" >/dev/null 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then report "ok-baseline.sh (포맷 정상)" 0; else report "ok-baseline.sh (포맷 정상)" 1 "기대 exit=0 / 실제 exit=$status"; fi

  status=0
  shfmt -d -i 2 "$FIXTURES/fail-fmt.sh" >/dev/null 2>&1 || status=$?
  if [ "$status" -ne 0 ]; then report "fail-fmt.sh (포맷 위반 차단)" 0; else report "fail-fmt.sh (포맷 위반 차단)" 1 "기대 exit≠0 / 실제 exit=$status"; fi
fi

echo "--- shellcheck -x ---"
if require_tool shellcheck; then
  status=0
  shellcheck -x "$FIXTURES/ok-baseline.sh" >/dev/null 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then report "ok-baseline.sh (지적 0건)" 0; else report "ok-baseline.sh (지적 0건)" 1 "기대 exit=0 / 실제 exit=$status"; fi

  status=0
  out=$(shellcheck -x "$FIXTURES/fail-shellcheck.sh" 2>&1) || status=$?
  if [ "$status" -ne 0 ] && grep -qF "SC2086" <<<"$out"; then
    report "fail-shellcheck.sh (SC2086 검출)" 0
  else
    report "fail-shellcheck.sh (SC2086 검출)" 1 "기대 exit≠0 + SC2086 / 실제 exit=$status"
  fi
fi

echo "--- bash -n (sh 파일 최종 문법 검사) ---"
status=0
bash -n "$FIXTURES/ok-baseline.sh" >/dev/null 2>&1 || status=$?
if [ "$status" -eq 0 ]; then report "ok-baseline.sh (문법 정상)" 0; else report "ok-baseline.sh (문법 정상)" 1 "기대 exit=0 / 실제 exit=$status"; fi

status=0
bash -n "$FIXTURES/fail-bash-syntax.sh" >/dev/null 2>&1 || status=$?
if [ "$status" -ne 0 ]; then report "fail-bash-syntax.sh (문법 오류 차단)" 0; else report "fail-bash-syntax.sh (문법 오류 차단)" 1 "기대 exit≠0 / 실제 exit=$status"; fi

echo "--- zsh -n (zsh 파일은 이것만 받는다) ---"
if require_tool zsh; then
  status=0
  zsh -n "$FIXTURES/ok-baseline.zsh" >/dev/null 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then report "ok-baseline.zsh (문법 정상)" 0; else report "ok-baseline.zsh (문법 정상)" 1 "기대 exit=0 / 실제 exit=$status"; fi

  status=0
  zsh -n "$FIXTURES/fail-zsh-syntax.zsh" >/dev/null 2>&1 || status=$?
  if [ "$status" -ne 0 ]; then report "fail-zsh-syntax.zsh (문법 오류 차단)" 0; else report "fail-zsh-syntax.zsh (문법 오류 차단)" 1 "기대 exit≠0 / 실제 exit=$status"; fi
fi

echo "--- pre-flight-check.sh (bin/hooks, 커밋 시점 배선) ---"
# 위 CLI 레벨 섹션은 "판정 로직이 맞는가"만 본다. validate_shell 자신의 오케스트레이션
# (확장자별 분기, .zsh는 zsh -n만 받는지, .sh 위반이 실제로 커밋을 막는지)은 여기서
# pre-flight-check.sh를 실제로 bash 호출해 검증한다(k8s-check.sh/aiops-check.sh/
# observability-check.sh와 동일한 패턴으로 격리 저장소에서 실제 호출까지 확인).
if [ -x "$PFC" ]; then
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

  # Case 1: .zsh 파일은 zsh -n만 받아야 한다. repeat 3; do ... done 은 zsh 문법으로는
  # 유효하지만 bash -n으로는 파스 에러다(위 헤더 참고). 이 케이스가 통과한다는 것 자체가
  # bash 계열 도구(shfmt/shellcheck/bash -n)가 .zsh 파일에 적용되지 않았다는 증거다.
  if require_tool zsh; then
    SR1="$PLUGIN_TMP/repo1"
    new_repo "$SR1"
    cp "$FIXTURES/ok-baseline.zsh" "$SR1/script.zsh"
    git -C "$SR1" add script.zsh
    status=$(run_pfc "$SR1")
    if [ "$status" -eq 0 ]; then
      report "zsh-only-dispatch (zsh 전용 문법 -> zsh -n만 적용되어 통과)" 0
    else
      report "zsh-only-dispatch (zsh 전용 문법 -> zsh -n만 적용되어 통과)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi
  fi

  # Case 2: .sh 포맷 위반이 실제로 커밋을 막는지(validate_shell이 main()에 배선돼
  # 있는지) 확인한다.
  if require_tool shfmt; then
    SR2="$PLUGIN_TMP/repo2"
    new_repo "$SR2"
    cp "$FIXTURES/fail-fmt.sh" "$SR2/script.sh"
    git -C "$SR2" add script.sh
    status=$(run_pfc "$SR2")
    if [ "$status" -eq 1 ] && grep -qF "shfmt 포맷이 맞지 않아" "$PLUGIN_TMP/out"; then
      report "sh-fmt-trigger-and-block (shfmt 위반 -> 차단)" 0
    else
      report "sh-fmt-trigger-and-block (shfmt 위반 -> 차단)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi
  fi

  # Case 3: explicit 모드의 상대 경로는 "명령을 친 위치" 기준으로 해석되어야 한다.
  # pre-flight-check.sh 는 인자 검증 전에 저장소 루트로 cd 하므로, 그 전의 CWD 를 기억해
  # 두지 않으면 서브디렉토리에서 실행했을 때 같은 이름의 루트 파일이 대신 검증된다.
  # 그러면 사용자가 지목한 파일은 한 번도 보지 않은 채 exit 0 이 나온다 — 이 저장소가
  # 반복해서 제거해 온 무검증 초록불이다(실측: rc=0 무출력, 절대경로로는 rc=1).
  # 루트에 "정상" 동명 파일을 두는 것이 핵심이다. 없으면 경로를 못 찾아 실패하므로
  # 오히려 증상이 드러나고, 있어야만 조용한 오검증으로 뒤집힌다.
  if require_tool shellcheck; then
    SR3="$PLUGIN_TMP/repo3"
    new_repo "$SR3"
    mkdir -p "$SR3/sub"
    cp "$FIXTURES/ok-baseline.sh" "$SR3/script.sh"
    cp "$FIXTURES/fail-shellcheck.sh" "$SR3/sub/script.sh"
    git -C "$SR3" add script.sh sub/script.sh

    status=0
    (cd "$SR3/sub" && QUIET=0 bash "$PFC" script.sh) >"$PLUGIN_TMP/out" 2>&1 || status=$?
    if [ "$status" -ne 0 ] && grep -qF "shellcheck" "$PLUGIN_TMP/out"; then
      report "explicit-relative-path (서브디렉토리 상대경로가 그 위치 기준으로 해석됨)" 0
    else
      report "explicit-relative-path (서브디렉토리 상대경로가 그 위치 기준으로 해석됨)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi

    # 오탐 회귀: 저장소 루트에서 준 상대 경로는 종전대로 루트 기준이어야 한다.
    status=0
    (cd "$SR3" && QUIET=0 bash "$PFC" script.sh) >"$PLUGIN_TMP/out" 2>&1 || status=$?
    if [ "$status" -eq 0 ]; then
      report "explicit-relative-path-from-root (루트 기준 해석은 그대로)" 0
    else
      report "explicit-relative-path-from-root (루트 기준 해석은 그대로)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi
  fi

  rm -rf "$PLUGIN_TMP"
else
  report "pre-flight-check.sh 배선 확인" 1 "bin/hooks/pre-flight-check.sh 를 찾을 수 없거나 실행 권한이 없습니다"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
