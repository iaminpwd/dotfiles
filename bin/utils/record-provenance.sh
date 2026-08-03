#!/usr/bin/env bash
set -euo pipefail

# lib/ 경로를 리터럴로 분리하여 shellcheck SC1091 오류 회피 (심볼릭 링크 호출 호환성 보장)
RECORD_PROVENANCE_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source-path=SCRIPTDIR
source "$RECORD_PROVENANCE_SCRIPT_DIR/../lib/git-relpath.sh"

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <file_path> <rule_source>[,<rule_source>...] <purpose>"
  echo "Example (단일 참고): $0 src/main.py aws/050-iac-standard.md \"Refactor authentication\""
  echo "Example (다중 참고): $0 src/main.py aws/050-iac-standard.md,aws/060-eks-standard.md \"Refactor authentication\""
  exit 1
fi

FILE_PATH="$1"
RULE_SOURCE="$2"
PURPOSE="$3"
ISO8601=$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
TARGET_DIR=".agent-state"
EDITS_LOG="$TARGET_DIR/edits.log"

mkdir -p "$TARGET_DIR"

# 로그 구분자(|) 오염 방지: agent-edits-hook.sh와 동일한 새니타이즈 규칙
clean() { printf '%s' "$1" | tr '\t\r\n|' '    ' | sed -e 's/^ *//' -e 's/ *$//'; }
PURPOSE_CLEAN=$(clean "$PURPOSE")

# dotfiles/contexts 위치 계산 (RECORD_PROVENANCE_SCRIPT_DIR은 이미 실경로 기준 bin/utils)
CONTEXTS_DIR="$(dirname "$(dirname "$RECORD_PROVENANCE_SCRIPT_DIR")")/contexts"

# 스킬 접두사(<skill>/파일명)가 없는 rule_source를 검증/보정한다.
# - contexts/ 전체에서 동일 파일명이 정확히 1곳뿐이면 자동으로 <skill>/파일명 으로 보정
# - 2곳 이상이면(예: 050-iac-standard.md가 aws/azure/aiops/openstack에 모두 존재) 모호함
#   -> 기록 자체를 누락시키지 않기 위해 AMBIGUOUS(...)로 치환해 반환한다
#      (감사 로그에서 "무엇을 하려다 막혔는지"가 사라지면 안 되기 때문)
# - 매칭이 없으면(임의 문자열) 입력값을 그대로 사용
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
    printf '%s' "$clean_src"
    return 0
    ;;
  esac
  if [ -d "$CONTEXTS_DIR" ]; then
    matches=$(find "$CONTEXTS_DIR" -iname "$clean_src" 2>/dev/null)
    count=$(printf '%s\n' "$matches" | grep -c .)
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
  case "$resolved_item" in AMBIGUOUS\(*) FAILED=1 ;; esac
  RULE_SOURCE_RESOLVED="${RULE_SOURCE_RESOLVED:+$RULE_SOURCE_RESOLVED,}$resolved_item"
done
if [ -z "$RULE_SOURCE_RESOLVED" ]; then
  echo "Usage: $0 <file_path> <rule_source>[,<rule_source>...] <purpose>" >&2
  exit 1
fi
RULE_SOURCE_CLEAN="$RULE_SOURCE_RESOLVED"
if [ "$FAILED" -eq 1 ]; then RESULT_TAG="FLAGGED"; else RESULT_TAG="SUCCESS"; fi

# agent-edits-hook.sh(PostToolUse)가 계산하는 상대경로와 동일한 기준으로 정규화
IFS=$'\t' read -r resolved git_root < <(resolve_target_and_git_root "$FILE_PATH")
if [ -n "$git_root" ]; then
  if [ "$resolved" = "$git_root" ]; then REL="$(basename "$resolved")"; else REL="${resolved#"$git_root"/}"; fi
else
  REL="$FILE_PATH"
fi

# Format: <ISO8601> | <파일경로> | <출처> | <작업 목적> | <결과>
# idempotency:bypass (로그 파일 연속 기록이므로 상태 검증 불필요)
#
# 아직 SUCCESS로 확정되지 않은 직전 라인(훅의 더미 "-" 또는 이전 FLAGGED 시도)이
# 있으면 새 줄을 추가하는 대신 그 자리에서 이번 결과로 보강(overwrite)한다.
# 없으면(훅 미기동 등) 기존처럼 append한다.
if [ -f "$EDITS_LOG" ] && awk -F' \\| ' -v r="$REL" '$2==r && $5!="SUCCESS" {found=1} END{exit !found}' "$EDITS_LOG"; then
  TMP="$EDITS_LOG.tmp.$$"
  awk -F' \\| ' -v r="$REL" -v src="agent:$RULE_SOURCE_CLEAN" -v purpose="$PURPOSE_CLEAN" -v tag="$RESULT_TAG" '
    $2==r && $5!="SUCCESS" { target=NR; tf1=$1; tf2=$2 }
    { line[NR]=$0 }
    END {
      for (i=1;i<=NR;i++) {
        if (i==target) {
          printf "%s | %s | %s | %s | %s\n", tf1, tf2, src, purpose, tag
        } else {
          print line[i]
        }
      }
    }' "$EDITS_LOG" >"$TMP" && mv "$TMP" "$EDITS_LOG"
  echo "✅ 미확정 라인을 [$RESULT_TAG]로 보강했습니다: $EDITS_LOG"
else
  # idempotency:bypass chronologically append log entry
  echo "$ISO8601 | $REL | agent:$RULE_SOURCE_CLEAN | $PURPOSE_CLEAN | $RESULT_TAG" >>"$EDITS_LOG"
  echo "✅ Logged edit to $EDITS_LOG ([$RESULT_TAG])"
fi

# 모호성 등으로 완전히 해소되지 못한 항목이 있으면, 기록은 남기되(FLAGGED)
# 호출자에게는 실패로 알려 재시도를 유도한다.
[ "$FAILED" -eq 0 ] || exit 1
