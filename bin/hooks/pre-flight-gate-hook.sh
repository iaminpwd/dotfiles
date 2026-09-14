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
# pfc는 bash로 실행하므로 파일 존재만, 직접 실행하는 rs는 실행 권한까지 확인한다.
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
  local untracked_files=() validator_files=()
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
        untracked_files+=("$git_root/$file")
      fi
    done < <(git -C "$git_root" ls-files --others --exclude-standard -z)
    if [ "${#untracked_files[@]}" -gt 0 ]; then
      git hash-object --no-filters -- "${untracked_files[@]}" || return 1
    fi
    # 검증기 변경도 성공 캐시를 무효화한다(외부 저장소의 정본 폴백 포함).
    validator_files=("$pfc" "$rs" "${BASH_SOURCE[0]}")
    while IFS= read -r -d '' file; do
      printf '%s\0' "$file"
      validator_files+=("$file")
    done < <(find "$DOTFILES_ROOT/bin" -type f -name '*.sh' -print0)
    # 경로와 내용은 모두 지문에 포함하되 파일마다 Git 프로세스를 띄우지 않는다.
    git hash-object --no-filters -- "${validator_files[@]}" || return 1
  } | git hash-object --stdin
}

DOCUMENTS_CHANGED=0
while IFS= read -r -d '' changed; do
  case "$changed" in *.md) DOCUMENTS_CHANGED=1 ;; esac
done < <(
  git -C "$git_root" diff --cached --name-only --no-renames -z
  git -C "$git_root" diff --name-only --no-renames -z
  git -C "$git_root" ls-files --others --exclude-standard -z
)

before=$(fingerprint) || before=""
[ -n "$before" ] && [ -f "$cache_file" ] && [ "$(cat "$cache_file")" = "$before" ] && exit 0

# 검사별 입력 지문. 문서 검사는 참조 경로의 존재와 Git 추적 목록도 보지만,
# 테스트 등록 검사는 활성 스킬의 tests/*.sh 내용만 본다. 공통 bin 검증기 변경은
# 양쪽 캐시를 무효화한다. .gitconfig 내용 변경은 어느 쪽도 무효화하지 않는다.
scope_fingerprint() {
  local scope=$1 dir
  if [ "$scope" = regression ]; then
    fingerprint
    return
  fi
  local dirs=()
  for dir in bin contexts; do
    [ ! -d "$git_root/$dir" ] || dirs+=("$git_root/$dir")
  done
  if [ "$scope" = prompt ]; then
    for dir in stow ansible .github; do
      [ ! -d "$git_root/$dir" ] || dirs+=("$git_root/$dir")
    done
  fi
  {
    printf '%s\0' "$git_root/README.md"
    if [ "${#dirs[@]}" -gt 0 ]; then
      find "${dirs[@]}" -path "$git_root/contexts/.*" -prune -o -print0 || return 1
    fi
  } | {
    local file rel
    local files=("$rs" "${BASH_SOURCE[0]}")
    while IFS= read -r -d '' file; do
      rel=${file#"$git_root/"}
      if [ "$scope" = prompt ]; then
        # 경로 생성·삭제는 참조 유효성을 바꿀 수 있으므로 확장자와 무관하게 포함한다.
        printf '%s\0' "$rel"
        case "$rel" in
        README.md | *.md | *.sh | *.yml | *.yaml | contexts/*.tsv | */.githooks/* | stow/mise/*) ;;
        *) continue ;;
        esac
      else
        case "$rel" in
        contexts/*/tests/*.sh | bin/*.sh) printf '%s\0' "$rel" ;;
        *) continue ;;
        esac
      fi
      if [ -f "$file" ]; then
        files+=("$file")
      elif [ -L "$file" ]; then
        readlink "$file" || return 1
      fi
    done
    if [ "$scope" = prompt ]; then
      printf 'examples=%s\n' "$DOCUMENTS_CHANGED"
      git -C "$git_root" ls-files -z || return 1
    fi
    git hash-object --no-filters -- "${files[@]}" || return 1
  } | git hash-object --stdin
}

write_success_cache() {
  local destination=$1 value=$2 tmp
  tmp=$(mktemp "$destination.XXXXXX") || return 0
  if ! { printf '%s\n' "$value" >"$tmp" && mv "$tmp" "$destination"; }; then
    rm -f "$tmp"
  fi
}

SCRIPTS=("$pfc")
SCOPES=()
SCOPE_HASHES=()
if [ "$git_root" -ef "$DOTFILES_ROOT" ]; then
  for scope in prompt tests regression; do
    case "$scope" in
    prompt) script="$git_root/bin/linters/prompt-lint.sh" ;;
    tests) script="$git_root/bin/linters/test-coverage-check.sh" ;;
    regression) script="$git_root/bin/hooks/stop-regression-check.sh" ;;
    esac
    [ -x "$script" ] || continue
    scope_hash=$(scope_fingerprint "$scope") || scope_hash=""
    scope_cache="$cache_file.$scope"
    if [ -n "$scope_hash" ] && [ -f "$scope_cache" ] && [ "$(cat "$scope_cache")" = "$scope_hash" ]; then
      continue
    fi
    SCRIPTS+=("$script")
    SCOPES+=("$scope")
    SCOPE_HASHES+=("$scope_hash")
  done
fi

# --pfc-args="--changed"는 SCRIPTS 중 경로에 pre-flight-check.sh가 포함된 항목에만
# run-suite.sh가 알아서 패스스루한다(run-suite.sh:run_script 참조).
#
# `env -C`(작업 디렉토리 변경)는 GNU coreutils 8.28+ 확장이라 BSD/macOS env 에는 없다.
# 이 훅은 macOS 에서도 도는데(pre-flight-check.sh 의 BSD sed 대응 주석과 같은 이유),
# 거기서 env 가 "illegal option -- C" 로 죽으면 그 0 아닌 종료 코드가 그대로 "검증 실패"로
# 해석돼 매 턴 decision:block 이 걸린다. 서브셸 cd 는 이식성 문제가 없고 부모 셸의 CWD 도
# 오염시키지 않는다.
OUT=""
RC=0
SCOPE_CACHEABLE=()
for i in "${!SCRIPTS[@]}"; do
  current_rc=0
  current_out=$(cd "$git_root" && PFC_PROFILE=stop PROMPT_LINT_REVIEW=0 PROMPT_LINT_EXAMPLES="$DOCUMENTS_CHANGED" "$rs" "${SCRIPTS[i]}" --pfc-args="--changed" 2>&1) || current_rc=$?
  OUT+="${current_out}"$'\n'
  [ "$current_rc" -eq 0 ] || RC=1
  if [ "$i" -gt 0 ]; then
    warnings=$(grep -E '\[WARNING\]|⚠' <<<"$current_out" | grep -vF '[WARNING] [ADVISORY]' || true)
    if [ "$current_rc" -eq 0 ] && [ -z "$warnings" ]; then
      SCOPE_CACHEABLE+=(1)
    else
      SCOPE_CACHEABLE+=(0)
    fi
  fi
done

after=$(fingerprint) || after=""
if [ -n "$before" ] && [ "$before" = "$after" ]; then
  # 다른 검사가 실패하거나 도구 부재로 건너뛰어져도, 실제 통과한 검사의 캐시는 저장한다.
  for i in "${!SCOPES[@]}"; do
    [ "${SCOPE_CACHEABLE[i]}" -eq 1 ] || continue
    scope_after=$(scope_fingerprint "${SCOPES[i]}") || scope_after=""
    if [ -n "${SCOPE_HASHES[i]}" ] && [ "${SCOPE_HASHES[i]}" = "$scope_after" ]; then
      write_success_cache "$cache_file.${SCOPES[i]}" "$scope_after"
    fi
  done
  cache_warnings=$(grep -E '\[WARNING\]|⚠' <<<"$OUT" | grep -vF '[WARNING] [ADVISORY]' || true)
  if [ "$RC" -eq 0 ] && [ -z "$cache_warnings" ]; then
    write_success_cache "$cache_file" "$before"
  fi
fi

if [ "$RC" -eq 0 ]; then
  # 통과: decision 없이 additionalContext만 조용히 실어 보낸다(차단·재응답 없음).
  # shellcheck disable=SC2016
  "$JQ" -n --arg ctx "$OUT" '
    { hookSpecificOutput: { hookEventName: "Stop", additionalContext: $ctx } }
  ' 2>/dev/null
  exit 0
fi

# shellcheck disable=SC2016
"$JQ" -n --arg reason "변경 영역 검사 실패: 아래 로그와 재현 명령으로 수정한 뒤 다시 검증하십시오." --arg ctx "$OUT" '
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
