#!/usr/bin/env bash
# test-record-provenance.sh
#
# record-provenance.sh는 rule_source가 "<스킬>/파일명" 형태가 아닐 때 contexts/ 전체에서 자동으로
# 스킬을 보정하는데, 동일 파일명이 여러 스킬에 존재하면 AMBIGUOUS로 표시하고 exit 1을
# 내야 한다(감사 로그 신뢰성의 핵심). 또한 agent-edits-hook.sh가 남긴 미확정("-") 라인이
# 있으면 새 줄을 추가하는 대신 그 자리를 SUCCESS/FLAGGED로 보강(overwrite)하는 병합 로직도
# 있다. 이 두 판정/병합 로직이 깨지면 근거 없는 SUCCESS가 찍히거나 로그가 중복될 수 있으므로
# 격리된 CWD에서 실제 contexts/ 디렉토리를 대상으로 고정한다.
#
# 사용: bash ~/dotfiles/contexts/prompt-architect/tests/test-record-provenance.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
RECORD_PROVENANCE="$REPO_ROOT/bin/utils/record-provenance.sh"

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

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/.agent-state/edits.log"

echo "=== record-provenance.sh 근거 보강/모호성 판정 로직 회귀 테스트 ==="

# 1. 이미 <스킬>/파일명 형태면 그대로 SUCCESS로 기록되어야 한다.
status=0
out=$(cd "$TMP" && bash "$RECORD_PROVENANCE" a.tf "aws/010-aws-core.md" "테스트 목적" 2>&1) || status=$?
if [ "$status" -eq 0 ] && grep -qF "agent:aws/010-aws-core.md" "$LOG" && grep -qF "| SUCCESS" "$LOG"; then
  report "skill-qualified (그대로 SUCCESS)" 0
else
  report "skill-qualified (그대로 SUCCESS)" 1 "exit=$status out=$out log=$(cat "$LOG" 2>/dev/null)"
fi

# 2. contexts/ 전체에서 유일하게 존재하는 파일명은 <스킬>/파일명으로 자동 보정되어야 한다.
#    (010-aws-core.md는 contexts/aws/references 아래 정확히 1곳에만 존재)
rm -f "$LOG"
status=0
out=$(cd "$TMP" && bash "$RECORD_PROVENANCE" b.tf "010-aws-core.md" "테스트 목적" 2>&1) || status=$?
if [ "$status" -eq 0 ] && grep -qF "agent:aws/010-aws-core.md" "$LOG" && grep -qF "| SUCCESS" "$LOG"; then
  report "unique-basename (자동 스킬 보정)" 0
else
  report "unique-basename (자동 스킬 보정)" 1 "exit=$status out=$out log=$(cat "$LOG" 2>/dev/null)"
fi

# 3. 여러 스킬에 동일 파일명이 있으면(050-iac-standard.md: aws/aiops/azure/openstack) FLAGGED + exit 1.
rm -f "$LOG"
status=0
out=$(cd "$TMP" && bash "$RECORD_PROVENANCE" c.tf "050-iac-standard.md" "테스트 목적" 2>&1) || status=$?
if [ "$status" -eq 1 ] && grep -qF "AMBIGUOUS(" "$LOG" && grep -qF "| FLAGGED" "$LOG" && grep -qF "여러 스킬에" <<<"$out"; then
  report "ambiguous-basename (AMBIGUOUS + FLAGGED + exit 1)" 0
else
  report "ambiguous-basename (AMBIGUOUS + FLAGGED + exit 1)" 1 "exit=$status out=$out log=$(cat "$LOG" 2>/dev/null)"
fi

# 4. 콤마로 여러 rule_source를 넘기면 하나라도 모호하면 전체가 FAILED(exit 1)여야 한다.
rm -f "$LOG"
status=0
out=$(cd "$TMP" && bash "$RECORD_PROVENANCE" d.tf "aws/010-aws-core.md,050-iac-standard.md" "테스트 목적" 2>&1) || status=$?
if [ "$status" -eq 1 ] && grep -qF "aws/010-aws-core.md,AMBIGUOUS(" "$LOG"; then
  report "multi-source (일부 모호하면 전체 FAILED)" 0
else
  report "multi-source (일부 모호하면 전체 FAILED)" 1 "exit=$status out=$out log=$(cat "$LOG" 2>/dev/null)"
fi

# 5. agent-edits-hook.sh가 남긴 미확정 라인("- " 목적, 5번째 필드 SUCCESS 아님)이 있으면
#    새 줄을 추가하는 대신 그 자리를 보강(overwrite)해야 한다 -> 총 줄 수 1 유지.
rm -f "$LOG"
mkdir -p "$(dirname "$LOG")"
echo "2026-01-01T00:00:00+00:00 | e.tf | hook:Edit | - | OK" >"$LOG"
status=0
out=$(cd "$TMP" && bash "$RECORD_PROVENANCE" e.tf "aws/010-aws-core.md" "테스트 목적" 2>&1) || status=$?
LINES=$(wc -l <"$LOG")
if [ "$status" -eq 0 ] && [ "$LINES" -eq 1 ] && grep -qF "agent:aws/010-aws-core.md" "$LOG" && grep -qF "| SUCCESS" "$LOG"; then
  report "미확정 라인 보강 (append 대신 overwrite, 1줄 유지)" 0
else
  report "미확정 라인 보강 (append 대신 overwrite, 1줄 유지)" 1 "exit=$status lines=$LINES log=$(cat "$LOG" 2>/dev/null)"
fi

# 6. 이미 SUCCESS로 확정된 라인은 더 이상 보강 대상이 아니므로, 재호출 시 새 줄이 append되어야 한다.
status=0
out=$(cd "$TMP" && bash "$RECORD_PROVENANCE" e.tf "aws/010-aws-core.md" "두 번째 목적" 2>&1) || status=$?
LINES=$(wc -l <"$LOG")
if [ "$status" -eq 0 ] && [ "$LINES" -eq 2 ]; then
  report "확정된 SUCCESS 라인 이후 재호출 (append)" 0
else
  report "확정된 SUCCESS 라인 이후 재호출 (append)" 1 "exit=$status lines=$LINES log=$(cat "$LOG" 2>/dev/null)"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
