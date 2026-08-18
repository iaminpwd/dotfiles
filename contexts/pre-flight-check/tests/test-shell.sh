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

  # Case 2b: `git mv` 로 옮기면서 함께 고친 파일도 검증 대상이어야 한다.
  #
  # git 은 유사도 50% 이상이면 변경을 R(rename)로 판정하는데, 대상 수집이
  # --diff-filter=ACM 이라 R 이 통째로 빠졌다. 그러면 대상 0건이 되어 게이트가 아무것도
  # 보지 않고 exit 0 을 낸다 — 출력 한 줄 없는 무검증 통과다(실측: old.sh 를 new.sh 로
  # 옮기며 SC2086 위반을 추가하니 R091 로 잡혀 통과. 같은 변경을 rename 없이 하면 차단).
  # 이 저장소도 stow 패키지 이관처럼 파일을 옮긴 커밋이 있었고, 그 커밋들은 이 게이트를
  # 통과한 게 아니라 거쳐 가지 않았다.
  if require_tool shellcheck; then
    SR2B="$PLUGIN_TMP/repo2b"
    new_repo "$SR2B"
    # 유사도가 임계값 위로 유지되도록 원본을 충분히 채운다. 전체를 갈아치우면 git 이
    # D+A 로 분해해 이 사각지대를 재현하지 못한다.
    {
      echo '#!/usr/bin/env bash'
      echo 'set -euo pipefail'
      for i in $(seq 1 40); do echo "echo \"line $i\""; done
    } >"$SR2B/old.sh"
    git -C "$SR2B" add old.sh
    git -C "$SR2B" -c core.hooksPath=/dev/null commit -q -m "chore: 이름 변경 픽스처"
    git -C "$SR2B" mv old.sh new.sh
    # SC2086 위반(따옴표 없는 변수 전개)을 추가한다.
    # (주석 줄을 그 린터 이름으로 시작하면 지시어로 파싱돼 SC1072/SC1073 으로 죽으므로
    #  이 줄들은 이름을 문두에 두지 않는다.)
    # idempotency:bypass (임시 픽스처에 대한 1회성 기록이라 상태 검증 불필요)
    # shellcheck disable=SC2016 # 픽스처에 리터럴로 써야 하는 문자열이라 전개되면 안 된다
    printf 'f=$1\necho $f\n' >>"$SR2B/new.sh"
    git -C "$SR2B" add new.sh

    # 실제로 R 로 잡히는 상태인지 먼저 확인한다. D+A 로 분해됐다면 의도한 사각지대를
    # 재현하지 못한 것이라, 통과하더라도 이 케이스는 아무것도 지키지 못한다.
    if git -C "$SR2B" diff --cached --name-status | grep -q '^R'; then
      status=$(run_pfc "$SR2B")
      if [ "$status" -eq 1 ] && grep -qF "shellcheck 지적 사항이 발견되어" "$PLUGIN_TMP/out"; then
        report "renamed-file-is-validated (git mv 한 파일도 검증 대상)" 0
      else
        report "renamed-file-is-validated (git mv 한 파일도 검증 대상)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
      fi
    else
      report "renamed-file-is-validated (git mv 한 파일도 검증 대상)" 1 "픽스처가 rename(R)으로 잡히지 않아 사각지대를 재현하지 못했습니다"
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

  # Case 4: tests/ 하위의 제외 범위는 "픽스처"까지만이어야 한다.
  # 예전엔 filter_target_files 가 */tests/* 를 통째로 뺐다. 제외의 근거는 언제나 의도적
  # 위반을 담은 픽스처였는데 범위가 테스트 스크립트 본체까지 덮어서, tests/ 아래 파일은
  # 무엇이든 대상 0건이 되어 검증기가 아무것도 보지 않고 exit 0 을 냈다 — explicit 모드를
  # 쓰는 pre-flight-live-hook.sh 가 AI 편집마다 "-> [✓]" 를 돌려주던 무검증 초록불이다
  # (실측: 추적 .sh 98개 중 59개가 그 상태, 같은 위반을 tests/ 밖에 두면 rc=1 로 차단).
  # 두 방향을 같이 고정한다. 한쪽만 두면 반대쪽으로 되돌아가도 잡지 못한다.
  if require_tool shellcheck; then
    SR4="$PLUGIN_TMP/repo4"
    new_repo "$SR4"
    mkdir -p "$SR4/tests/fixtures-shell"
    cp "$FIXTURES/fail-shellcheck.sh" "$SR4/tests/real-test.sh"
    cp "$FIXTURES/fail-shellcheck.sh" "$SR4/tests/fixtures-shell/fail-x.sh"
    git -C "$SR4" add tests/real-test.sh tests/fixtures-shell/fail-x.sh

    status=0
    (cd "$SR4" && QUIET=0 bash "$PFC" tests/real-test.sh) >"$PLUGIN_TMP/out" 2>&1 || status=$?
    if [ "$status" -ne 0 ] && grep -qF "shellcheck" "$PLUGIN_TMP/out"; then
      report "tests-script-is-linted (픽스처가 아닌 테스트 스크립트는 검증 대상)" 0
    else
      report "tests-script-is-linted (픽스처가 아닌 테스트 스크립트는 검증 대상)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi

    status=0
    (cd "$SR4" && QUIET=0 bash "$PFC" tests/fixtures-shell/fail-x.sh) >"$PLUGIN_TMP/out" 2>&1 || status=$?
    if [ "$status" -eq 0 ]; then
      report "tests-fixture-still-excluded (의도적 위반 픽스처는 종전대로 제외)" 0
    else
      report "tests-fixture-still-excluded (의도적 위반 픽스처는 종전대로 제외)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
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
