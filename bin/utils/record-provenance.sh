#!/usr/bin/env bash
set -euo pipefail

# macOS 기본 BSD readlink에는 -f가 없다. symlink로 호출해도 원본 저장소의
# lib/ 및 contexts/를 찾도록 plain readlink와 물리 경로만 사용한다.
rp_resolve_script_path() {
  local path=$1 dir target hops=0
  while [ -L "$path" ]; do
    hops=$((hops + 1))
    [ "$hops" -le 40 ] || return 1
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

RECORD_PROVENANCE_SCRIPT_PATH=$(rp_resolve_script_path "${BASH_SOURCE[0]}") || {
  echo "[ERROR] provenance 스크립트 경로를 확인하지 못했습니다." >&2
  exit 1
}
RECORD_PROVENANCE_SCRIPT_DIR=$(dirname "$RECORD_PROVENANCE_SCRIPT_PATH")
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC1091 # 경로는 symlink 해석 후 런타임에 계산한다.
source "$RECORD_PROVENANCE_SCRIPT_DIR/../lib/git-relpath.sh"

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <file_path> <rule_source>[,<rule_source>...] <purpose>"
  echo "Example (단일 참고): $0 src/main.py dotfiles/010-core.md \"Refactor authentication\""
  echo "Example (다중 참고): $0 src/main.py dotfiles/010-core.md,aiops/SKILL.md \"Refactor authentication\""
  exit 1
fi

FILE_PATH="$1"
RULE_SOURCE="$2"
PURPOSE="$3"
ISO8601=$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

# agent-edits-hook.sh(PostToolUse)가 계산하는 상대경로와 동일한 기준으로 정규화
IFS=$'\t' read -r resolved git_root < <(resolve_target_and_git_root "$FILE_PATH")
if [ -n "$git_root" ]; then
  if [ "$resolved" = "$git_root" ]; then REL="$(basename "$resolved")"; else REL="${resolved#"$git_root"/}"; fi
else
  REL="$FILE_PATH"
fi

# 로그 위치도 REL과 같은 기준(git 최상위)으로 고정한다. 예전엔 CWD 상대(".agent-state")여서
# 서브디렉토리에서 실행하면 <cwd>/.agent-state/edits.log가 새로 생기는데, 정작 기록되는 경로는
# git 루트 기준이라 둘이 어긋났다(실측: sub/에서 실행 -> sub/.agent-state/edits.log에
# "sub/a.txt"가 기록됨). 그러면 감사 로그가 디렉토리마다 쪼개져 base.AGENTS.md 9장이 지시하는
# ".agent-state/edits.log 조회"가 이력의 일부만 보게 되고, 아래 "미확정 라인 보강"도 훅이
# <git루트>에 남긴 줄을 영영 찾지 못해 중복 append만 쌓인다.
# git 저장소가 아니면(추적 밖 경로) 종전대로 CWD 기준으로 남긴다.
TARGET_DIR="${git_root:-.}/.agent-state"
EDITS_LOG="$TARGET_DIR/edits.log"

mkdir -p "$TARGET_DIR"

# 로그 구분자(|) 오염 방지: agent-edits-hook.sh와 동일한 새니타이즈 규칙
clean() { printf '%s' "$1" | tr '\t\r\n|' '    ' | sed -e 's/^ *//' -e 's/ *$//'; }
PURPOSE_CLEAN=$(clean "$PURPOSE")

# dotfiles/contexts 위치 계산 (RECORD_PROVENANCE_SCRIPT_DIR은 이미 실경로 기준 bin/utils)
CONTEXTS_DIR="$(dirname "$(dirname "$RECORD_PROVENANCE_SCRIPT_DIR")")/contexts"

# rule_source를 검증/보정한다.
# - <skill>/<파일명> 형태면 해당 활성 contexts/<skill>/ 안에 그 basename이 실제로
#   존재해야 한다. 없으면 MISSING(...)으로 남기고 FLAGGED 처리한다.
# - 스킬 접두사가 없으면 contexts/ 전체에서 동일 파일명이 정확히 1곳뿐일 때
#   <skill>/파일명 으로 자동 보정한다.
# - 2곳 이상이면 모호함을 AMBIGUOUS(...)로 기록한다.
# - 접두사 없는 이름이 어디에도 없으면 기존 계약대로 입력값 자체를 외부/논리 근거명으로
#   보고 그대로 사용한다.
#
# 주의: 이 함수는 항상 command substitution($(...))으로 호출되어 서브셸에서 실행되므로,
# 모호성 여부는 전역 변수가 아니라 반환 문자열의 "AMBIGUOUS(" 접두사로만 호출부에 전달된다.
resolve_source() {
  local src clean_src matches count skill candidates
  src="$1"
  clean_src=$(clean "$src")
  [ -n "$clean_src" ] || return 0
  case "$clean_src" in
  */*)
    local skill_name file_name qualified_matches qualified_count
    skill_name="${clean_src%%/*}"
    file_name="${clean_src#*/}"

    # 문서화된 qualified 형식은 <skill>/<파일명> 한 단계다. 숨김/없는 스킬이나
    # 추가 경로 조각은 활성 rule_source로 인정하지 않는다.
    if [ -z "$skill_name" ] || [ -z "$file_name" ] ||
      [[ "$skill_name" = .* ]] || [[ "$file_name" = */* ]] ||
      [ ! -d "$CONTEXTS_DIR/$skill_name" ]; then
      echo "❌ 존재하지 않는 rule_source: $clean_src" >&2
      printf 'MISSING(%s)' "$clean_src"
      return 0
    fi

    qualified_matches=$(find "$CONTEXTS_DIR/$skill_name" -type f -iname "$file_name" -print 2>/dev/null)
    qualified_count=$(printf '%s\n' "$qualified_matches" | grep -c . || true)
    if [ "$qualified_count" -eq 1 ]; then
      printf '%s/%s' "$skill_name" "$file_name"
    elif [ "$qualified_count" -eq 0 ]; then
      echo "❌ 존재하지 않는 rule_source: $clean_src" >&2
      printf 'MISSING(%s)' "$clean_src"
    else
      echo "❌ '$clean_src'는 같은 스킬 안에 동일 basename이 여러 개 있어 모호합니다." >&2
      printf 'AMBIGUOUS(%s)' "$clean_src"
    fi
    return 0
    ;;
  esac
  if [ -d "$CONTEXTS_DIR" ]; then
    # 점으로 시작하는 컨텍스트 디렉토리(과거 .archive 같은 비활성 트리)는
    # 후보에서 뺀다. 폐기된 룰북이 살아있는 룰북과 파일명을 대량으로 공유하기 때문에
    # (실측: azure/openstack 을 .archive 로 옮긴 뒤 080-database-standard.md 는 활성
    # 스킬 1곳에만 있는데도 "후보: .archive,.archive,aws" 로 모호 판정되어 exit 1 +
    # FLAGGED 가 됐다), 제외하지 않으면 정상적인 근거 기록이 막힌다.
    # 반대 방향도 있다: .archive 에만 있는 이름은 유일 매치로 통과해 스킬이 리터럴
    # ".archive" 로 보정되고, `agent:.archive/026-networking-standard.md` 라는 폐기
    # 룰북 근거가 SUCCESS 로 기록됐다(실측).
    matches=$(find "$CONTEXTS_DIR" -path "$CONTEXTS_DIR/.*" -prune -o -iname "$clean_src" -print 2>/dev/null)
    # grep -c 는 카운트가 0일 때 "0" 을 찍고도 종료 코드 1을 낸다. 이 함수는 항상
    # $(resolve_source ...) 로 호출되는데, 명령 치환 서브셸 안에서는 set -e 가 이 대입을
    # 죽이지 않아 지금까지 발현되지 않았다(실측: 최상위·함수 직접 호출에서는 exit 1 로 죽고,
    # 명령 치환 안에서는 살아남는다). 즉 호출 방식 하나에 기대고 있던 셈이라, 누가 이 함수를
    # 직접 부르는 순간 무매치 rule_source 가 스크립트를 조용히 죽인다. || true 로 흡수한다.
    count=$(printf '%s\n' "$matches" | grep -c . || true)
    if [ "$count" -eq 1 ]; then
      skill=$(dirname "$matches" | sed -E "s#^${CONTEXTS_DIR}/([^/]+)/.*#\1#")
      printf '%s/%s' "$skill" "$clean_src"
      return 0
    elif [ "$count" -gt 1 ]; then
      candidates=$(printf '%s\n' "$matches" | sed -E "s#^${CONTEXTS_DIR}/([^/]+)/.*#\1#" | paste -sd, -)
      echo "❌ '$clean_src'는 여러 스킬에 동일한 이름으로 존재해 모호합니다. 후보: $candidates" >&2
      echo "   -> 다음 실행 시 '<스킬>/$clean_src' 형태로 명시하면 이번에 남는 FLAGGED 라인이 보강됩니다." >&2
      printf 'AMBIGUOUS(%s:candidates=%s)' "$clean_src" "$candidates"
      return 0
    fi
  fi
  printf '%s' "$clean_src"
  return 0
}

# 콤마로 구분된 다중 룰 파일 참조를 각각 검증/보정한 뒤 다시 콤마로 결합한다.
FAILED=0
RULE_SOURCE_RESOLVED=""
IFS=',' read -ra SRC_ITEMS <<<"$RULE_SOURCE"
for item in "${SRC_ITEMS[@]}"; do
  resolved_item=$(resolve_source "$item")
  [ -n "$resolved_item" ] || continue
  case "$resolved_item" in
  AMBIGUOUS\(* | MISSING\(*) FAILED=1 ;;
  esac
  RULE_SOURCE_RESOLVED="${RULE_SOURCE_RESOLVED:+$RULE_SOURCE_RESOLVED,}$resolved_item"
done
if [ -z "$RULE_SOURCE_RESOLVED" ]; then
  echo "Usage: $0 <file_path> <rule_source>[,<rule_source>...] <purpose>" >&2
  exit 1
fi
RULE_SOURCE_CLEAN="$RULE_SOURCE_RESOLVED"
if [ "$FAILED" -eq 1 ]; then RESULT_TAG="FLAGGED"; else RESULT_TAG="SUCCESS"; fi

# Format: <ISO8601> | <파일경로> | <출처> | <작업 목적> | <결과>
# idempotency:bypass (로그 파일 연속 기록이므로 상태 검증 불필요)
#
# 같은 파일의 "가장 최근" 로그가 보강 가능한 상태일 때만 그 자리를 갱신한다.
# - hook:* | - | OK      : 성공 편집의 자동 더미 라인
# - agent:* | <same purpose> | FLAGGED : 같은 작업 목적의 provenance 재시도
# FLAGGED라도 purpose가 다르면 독립 작업이므로 기존 행을 보존하고 새 행을 append한다.
# ERROR는 실패한 편집이라는 독립 감사 이력이므로 절대 SUCCESS로 덮어쓰지 않는다.
# 더 오래된 OK 뒤에 최신 ERROR/SUCCESS가 있는 경우도 과거 행을 소급 보강하지 않는다.
is_latest_row_enrichable() {
  awk -F' \\| ' -v r="$REL" -v new_purpose="$PURPOSE_CLEAN" '
    $2==r { src=$3; purpose=$4; result=$5 }
    END {
      ok = ((src ~ /^hook:/ && purpose=="-" && result=="OK") ||
            (src ~ /^agent:/ && result=="FLAGGED" && purpose==new_purpose))
      exit !ok
    }
  ' "$EDITS_LOG"
}

if [ -f "$EDITS_LOG" ] && is_latest_row_enrichable; then
  # predictable filename이나 PID 조합 대신 mktemp를 사용한다. 같은 디렉터리에 만들어야
  # 최종 mv가 같은 파일시스템 안에서 원자적 교체가 되고, 선점 symlink도 따라가지 않는다.
  TMP=$(mktemp "${EDITS_LOG}.tmp.XXXXXX")
  trap 'rm -f "$TMP"' EXIT HUP INT TERM
  awk -F' \\| ' -v r="$REL" -v src="agent:$RULE_SOURCE_CLEAN" -v purpose="$PURPOSE_CLEAN" -v tag="$RESULT_TAG" '
    $2==r {
      target=NR
      tf1=$1
      tf2=$2
      target_src=$3
      target_purpose=$4
      target_result=$5
    }
    { line[NR]=$0 }
    END {
      enrich = ((target_src ~ /^hook:/ && target_purpose=="-" && target_result=="OK") ||
                (target_src ~ /^agent:/ && target_result=="FLAGGED" && target_purpose==purpose))
      for (i=1;i<=NR;i++) {
        if (enrich && i==target) {
          printf "%s | %s | %s | %s | %s\n", tf1, tf2, src, purpose, tag
        } else {
          print line[i]
        }
      }
    }' "$EDITS_LOG" >"$TMP"
  mv "$TMP" "$EDITS_LOG"
  trap - EXIT HUP INT TERM
  echo "✅ 미확정 라인을 [$RESULT_TAG]로 보강했습니다: $EDITS_LOG"
else
  # idempotency:bypass chronologically append log entry
  echo "$ISO8601 | $REL | agent:$RULE_SOURCE_CLEAN | $PURPOSE_CLEAN | $RESULT_TAG" >>"$EDITS_LOG"
  echo "✅ Logged edit to $EDITS_LOG ([$RESULT_TAG])"
fi

# 모호성 등으로 완전히 해소되지 못한 항목이 있으면, 기록은 남기되(FLAGGED)
# 호출자에게는 실패로 알려 재시도를 유도한다.
[ "$FAILED" -eq 0 ] || exit 1
