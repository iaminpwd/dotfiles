#!/usr/bin/env bash
# Stop 시 마지막 성공 검증 이후 내용이 달라졌을 때만 검사한다.
# 실패 및 검사 중 변경은 캐시하지 않으며 stop_hook_active로 재응답 루프를 방지한다.
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

# 구분자를 명시하는 이유: @tsv 출력을 기본 IFS(공백 포함)로 읽으면 공백이 든 cwd 가 잘려
# 나가고 그 뒷조각이 stop_hook_active 로 들어간다(실측: cwd="/home/ubuntu/my repo/sub"
# -> cwd="/home/ubuntu/my"). 그러면 뒤의 git -C "$cwd" 가 실패해 fail-open 으로 조용히
# 빠지면서, 경로에 공백이 있는 프로젝트에서는 이 게이트가 통째로 안 돈다.
#
# 다만 탭도 쓸 수 없다. 탭은 IFS 공백문자라 `IFS=$'\t' read` 가 연속 탭을 구분자 하나로
# 합치는데, cwd 는 정상적으로 빌 수 있어(페이로드에 cwd 가 없는 경우) 그때 필드가 밀린다
# (실측: 빈 cwd + false -> cwd="false", stop_hook_active=""). unit separator(\037)는 IFS
# 공백이 아니라 연속해도 합쳐지지 않는다. agent-edits-hook.sh 가 같은 이유로 같은 구분자를
# 쓴다(그쪽은 이 밀림이 감사 로그 훼손으로 실제 발현했다).
# shellcheck disable=SC2016
IFS=$'\037' read -r cwd stop_hook_active < <(
  "$JQ" -r '[(.cwd // ""), (.stop_hook_active // false)] | map(tostring) | join("\u001f")' <<<"$payload" 2>/dev/null
) || exit 0

[ "$stop_hook_active" = "true" ] && exit 0
[ -n "${cwd:-}" ] || exit 0

git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0

pfc="$git_root/bin/hooks/pre-flight-check.sh"
rs="$git_root/bin/hooks/run-suite.sh"
# pfc 는 -f, rs 는 -x 로 판정하는 이유는 pre-flight-live-hook.sh 의 같은 지점 주석 참조
# (pfc 는 run-suite.sh 에 인자로 넘겨 bash 로 실행되므로 실행 권한이 필요 없고, 예전의
#  -x 판정은 실행 권한 없는 옵트인 저장소에서 이 훅만 조용히 빠지게 만들었다).
if [[ "$git_root/" == "$HOME/workspace/"* ]] || [ "$git_root" -ef "$DOTFILES_ROOT" ]; then
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

# Git 메타데이터 안에 저장해 검사 대상과 사용자 작업 트리를 오염시키지 않는다.
cache_file=$(git -C "$git_root" rev-parse --git-path pre-flight-stop-success)
case "$cache_file" in
/*) ;;
*) cache_file="$git_root/$cache_file" ;;
esac

fingerprint() {
  local file
  {
    git -C "$git_root" rev-parse HEAD 2>/dev/null || printf 'unborn\n'
    git -C "$git_root" status --porcelain=v1 -z || return 1
    git -C "$git_root" diff --no-ext-diff --no-textconv --binary || return 1
    git -C "$git_root" diff --cached --no-ext-diff --no-textconv --binary || return 1
    # untracked는 diff에 없으므로 경로와 내용을 함께 포함한다.
    while IFS= read -r -d '' file; do
      printf '%s\0' "$file"
      if [ -L "$git_root/$file" ]; then
        readlink "$git_root/$file" || return 1
      else
        git hash-object --no-filters -- "$git_root/$file" || return 1
      fi
    done < <(git -C "$git_root" ls-files --others --exclude-standard -z)
    # 검증기 변경도 성공 캐시를 무효화한다(외부 저장소의 정본 폴백 포함).
    for file in "$pfc" "$rs" "${BASH_SOURCE[0]}"; do
      git hash-object --no-filters -- "$file" || return 1
    done
    while IFS= read -r -d '' file; do
      printf '%s\0' "$file"
      git hash-object --no-filters -- "$file" || return 1
    done < <(find "$DOTFILES_ROOT/bin" -type f -name '*.sh' -print0)
  } | git hash-object --stdin
}

before=$(fingerprint) || before=""
[ -n "$before" ] && [ -f "$cache_file" ] && [ "$(cat "$cache_file")" = "$before" ] && exit 0

SCRIPTS=("$pfc")

# prompt-lint.sh / test-coverage-check.sh는 저장소별이 아니라 dotfiles 코퍼스 전역
# 검사라(test-coverage-check.sh는 자기 물리적 위치 기준으로 항상 dotfiles 자신만 본다),
# 대상 저장소가 dotfiles 자신일 때만 의미가 있다.
if [ "$git_root" -ef "$DOTFILES_ROOT" ]; then
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
OUT=$(cd "$git_root" && PFC_PROFILE=full "$rs" "${SCRIPTS[@]}" --pfc-args="--changed" 2>&1)
RC=$?

if [ "$RC" -eq 0 ]; then
  after=$(fingerprint) || after=""
  # 명시된 권고만 캐시를 허용하고, 미실행·알 수 없는 경고는 재검사한다.
  cache_warnings=$(grep -E '\[WARNING\]|⚠' <<<"$OUT" | grep -vF '[WARNING] [ADVISORY]' || true)
  if [ -n "$before" ] && [ "$before" = "$after" ] && [ -z "$cache_warnings" ]; then
    cache_tmp=$(mktemp "$cache_file.XXXXXX") || cache_tmp=""
    if [ -n "$cache_tmp" ]; then
      if ! { printf '%s\n' "$before" >"$cache_tmp" && mv "$cache_tmp" "$cache_file"; }; then
        rm -f "$cache_tmp"
      fi
    fi
  fi
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
