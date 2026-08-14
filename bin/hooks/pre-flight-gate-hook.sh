#!/usr/bin/env bash
# pre-flight-gate-hook.sh - 에이전트가 응답(턴)을 끝내려는 시점(Stop)에, base.AGENTS.md의
# "Pre-Flight Gate" MUST 룰(완료 선언 직전 통합 검증)을 기계적으로 강제하는 훅.
#
# 범위는 의도적으로 가볍게 셋으로 한정한다: pre-flight-check.sh(--changed) + prompt-lint.sh
# + test-coverage-check.sh. contexts/*/tests/run.sh 스킬별 회귀 스위트(checkov/tflint/sam 등
# 무거운 외부 도구 반복 호출)는 여기서 뺐다 — git/.githooks/pre-push가 이미 "건드린 스킬만"
# 스마트하게 골라 push 시점에 돌리고 있고(코어 로직(bin/lib/*, pre-flight-check.sh) 변경은
# pre-push 케이스에 전체 스킬 트리거로 이미 보강해뒀다), 턴마다 스킬 스위트 전체를 또 돌리면
# "지금 이 변경이 안전한가"가 아니라 "검증기 자체가 여전히 맞는가"까지 매턴 재확인하는
# 셈이라 순수 낭비다.
#
# 위 3개는 run-suite.sh에 명시적 스크립트 경로로 넘겨서 돌린다(무인자가 아니므로
# contexts/*/tests/run.sh 가 전량 딸려오는 기본 전체 수집 분기는 안 탐). 성공 시에도
# 완전 무음이면 "통과했다"와 "훅이 애초에 안 돌았다"가 구분이 안 되므로, run-suite.sh의
# 압축된 "-> [✓] <경로>" 출력을 decision:block 없이(=차단·재응답 유발 없이)
# additionalContext로만 조용히 실어 보낸다 — 대화 메시지로는 안 보이고 에이전트
# 컨텍스트에만 쌓이는 채널이라 몇 줄 수준이면 비용이 감내할 만하다. 실패 시엔 지금도
# run-suite.sh가 압축 없이 원본을 그대로 보여준다.
#
# 변경사항이 전혀 없는 턴(순수 Q&A 등)에는 아무것도 실행하지 않고 조용히 빠진다.
#
# fail-open + stop_hook_active 체크는 공식 가이드의 무한루프 방지 패턴을 그대로 따른다:
# 이 훅이 한 번 decision:block을 걸어 에이전트가 재응답했는데 그 재응답에서도 다시
# 실패하면, 다시 block을 걸면 무한루프가 된다. stop_hook_active가 true(=이미 Stop 훅
# 컨텍스트 안)면 더 이상 막지 않고 조용히 통과시킨다.
set -uo pipefail

PFG_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# 정본 저장소 루트는 이 훅의 물리적 위치에서 구한다. 예전엔 "$HOME/dotfiles" 를 하드코딩해서,
# 저장소가 그 경로에 없으면(CI 체크아웃 경로, 여러 벌 클론, ~/src/dotfiles 같은 개인 배치)
# 폴백이 존재하지 않는 파일을 가리키고 아래 `[ -x "$rs" ] || exit 0` 에 걸려 훅이 조용히
# 빠졌다 — 게이트가 통째로 비어 있는데 아무 표시도 나지 않는다(실측: GitHub Actions 에서
# 이 경로로 회귀 테스트가 실패). PFG_SCRIPT_DIR 은 readlink -f 로 심볼릭 링크를 이미
# 해소했으므로 ~/.local/bin 링크를 통해 호출돼도 정본 위치를 가리킨다
# (prompt-lint.sh / test-coverage-check.sh / generate-context-index.sh 와 동일한 관용구).
DOTFILES_ROOT=$(cd "$PFG_SCRIPT_DIR/../.." && pwd)
# shellcheck source-path=SCRIPTDIR
source "$PFG_SCRIPT_DIR/../lib/jq-resolve.sh"

JQ=$(resolve_jq)
{ [ -n "$JQ" ] && "$JQ" --version >/dev/null 2>&1; } || exit 0

payload=$(cat)

# IFS=$'\t' 필수: @tsv 출력을 기본 IFS(공백 포함)로 읽으면 공백이 든 cwd 가 잘려
# 나가고 그 뒷조각이 stop_hook_active 로 들어간다(실측: cwd="/home/ubuntu/my repo/sub"
# -> cwd="/home/ubuntu/my"). 그러면 뒤의 git -C "$cwd" 가 실패해 fail-open 으로 조용히
# 빠지면서, 경로에 공백이 있는 프로젝트에서는 이 게이트가 통째로 안 돈다.
# 형제 훅(pre-flight-live-hook.sh, agent-edits-hook.sh)은 원래부터 IFS 를 지정하고 있었다.
# shellcheck disable=SC2016
IFS=$'\t' read -r cwd stop_hook_active < <(
  "$JQ" -r '[(.cwd // ""), (.stop_hook_active // false)] | @tsv' <<<"$payload" 2>/dev/null
) || exit 0

[ "$stop_hook_active" = "true" ] && exit 0
[ -n "${cwd:-}" ] || exit 0

git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0

pfc="$git_root/bin/hooks/pre-flight-check.sh"
rs="$git_root/bin/hooks/run-suite.sh"
# pfc 는 -f, rs 는 -x 로 판정하는 이유는 pre-flight-live-hook.sh 의 같은 지점 주석 참조
# (pfc 는 run-suite.sh 에 인자로 넘겨 bash 로 실행되므로 실행 권한이 필요 없고, 예전의
#  -x 판정은 실행 권한 없는 옵트인 저장소에서 이 훅만 조용히 빠지게 만들었다).
if [[ "$git_root/" == "$HOME/workspace/"* ]] || [ "$(basename "$git_root")" = "dotfiles" ]; then
  [ -f "$pfc" ] || pfc="$DOTFILES_ROOT/bin/hooks/pre-flight-check.sh"
  [ -x "$rs" ] || rs="$DOTFILES_ROOT/bin/hooks/run-suite.sh"
elif [ -f "$git_root/pre-flight-check.sh" ]; then
  pfc="$git_root/pre-flight-check.sh"
  # 옵트인 저장소는 자체 run-suite.sh를 두는 게 아니라 pre-flight-check.sh 심볼릭
  # 링크 하나만 옵트인하는 게 기존 관례(git/.githooks/pre-commit과 동일)라, 러너는
  # 항상 dotfiles 정본을 쓴다.
  rs="$DOTFILES_ROOT/bin/hooks/run-suite.sh"
else
  exit 0
fi
[ -f "$pfc" ] || exit 0
[ -x "$rs" ] || exit 0

# 커밋되지 않은 변경분이 하나도 없으면(순수 대화 턴 등) 검증할 게 없으므로 조용히 빠진다.
[ -n "$(git -C "$git_root" status --porcelain 2>/dev/null)" ] || exit 0

SCRIPTS=("$pfc")

# prompt-lint.sh / test-coverage-check.sh는 저장소별이 아니라 dotfiles 코퍼스 전역
# 검사라(test-coverage-check.sh는 자기 물리적 위치 기준으로 항상 dotfiles 자신만 본다),
# 대상 저장소가 dotfiles 자신일 때만 의미가 있다.
if [ "$(basename "$git_root")" = "dotfiles" ]; then
  prompt_lint="$git_root/bin/linters/prompt-lint.sh"
  [ -x "$prompt_lint" ] || prompt_lint="$DOTFILES_ROOT/bin/linters/prompt-lint.sh"
  [ -x "$prompt_lint" ] && SCRIPTS+=("$prompt_lint")

  test_coverage="$git_root/bin/linters/test-coverage-check.sh"
  [ -x "$test_coverage" ] || test_coverage="$DOTFILES_ROOT/bin/linters/test-coverage-check.sh"
  [ -x "$test_coverage" ] && SCRIPTS+=("$test_coverage")
fi

# --pfc-args="--changed"는 SCRIPTS 중 경로에 pre-flight-check.sh가 포함된 항목에만
# run-suite.sh가 알아서 패스스루한다(run-suite.sh:run_script 참조).
#
# `env -C`(작업 디렉토리 변경)는 GNU coreutils 8.28+ 확장이라 BSD/macOS env 에는 없다.
# 이 훅은 macOS 에서도 도는데(pre-flight-check.sh 의 BSD sed 대응 주석과 같은 이유),
# 거기서 env 가 "illegal option -- C" 로 죽으면 그 0 아닌 종료 코드가 그대로 "검증 실패"로
# 해석돼 매 턴 decision:block 이 걸린다. 서브셸 cd 는 이식성 문제가 없고 부모 셸의 CWD 도
# 오염시키지 않는다.
OUT=$(cd "$git_root" && "$rs" "${SCRIPTS[@]}" --pfc-args="--changed" 2>&1)
RC=$?

if [ "$RC" -eq 0 ]; then
  # 통과: decision 없이 additionalContext만 조용히 실어 보낸다(차단·재응답 없음).
  # shellcheck disable=SC2016
  "$JQ" -n --arg ctx "$OUT" '
    { hookSpecificOutput: { hookEventName: "Stop", additionalContext: $ctx } }
  ' 2>/dev/null
  exit 0
fi

# shellcheck disable=SC2016
"$JQ" -n --arg reason "Pre-Flight Gate 실패: 완료 선언 전 확인이 필요합니다." --arg ctx "$OUT" '
  {
    decision: "block",
    reason: $reason,
    hookSpecificOutput: {
      hookEventName: "Stop",
      additionalContext: $ctx
    }
  }
' 2>/dev/null
exit 0
