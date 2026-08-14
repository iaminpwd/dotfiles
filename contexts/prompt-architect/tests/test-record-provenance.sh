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

# 3. 여러 "활성" 스킬에 동일 파일명이 있으면(050-iac-standard.md: aws/aiops) FLAGGED + exit 1.
#    (azure/openstack 에도 같은 이름이 있지만 .archive 로 옮겨져 후보에서 빠진다 — 아래 7 참조.)
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

# -----------------------------------------------------------------------------
# 7~8. 폐기된 스킬(contexts/.archive/)이 후보에 섞이면 안 된다.
#
# azure/openstack 을 .archive 로 옮긴 뒤, 폐기된 룰북이 살아있는 룰북과 파일명을 대량으로
# 공유하게 됐다(005/020/025/030/040/050/080/090/100 등). 스킬 보정 find 가 그것을 함께
# 세면 양방향으로 깨진다 — 둘 다 실측으로 재현했다.
# 픽스처를 합성하지 않고 실제 코퍼스를 쓰는 것은 이 스위트의 기존 방침이므로(헤더 참조),
# 전제가 무너지면 원인을 알 수 있게 먼저 확인한다.
ARCHIVE_ONLY="026-networking-standard.md"      # .archive/openstack 에만 존재
ACTIVE_PLUS_ARCHIVE="080-database-standard.md" # 활성 aws 1곳 + .archive 2곳

premise_ok=1
[ -e "$REPO_ROOT/contexts/.archive/openstack/references/$ARCHIVE_ONLY" ] || premise_ok=0
[ -e "$REPO_ROOT/contexts/aws/references/$ACTIVE_PLUS_ARCHIVE" ] || premise_ok=0
[ "$(find "$REPO_ROOT/contexts/.archive" -name "$ACTIVE_PLUS_ARCHIVE" | wc -l)" -ge 1 ] || premise_ok=0

if [ "$premise_ok" -eq 0 ]; then
  report "archive 제외 케이스 전제 확인" 1 "코퍼스가 바뀌어 픽스처 전제가 깨졌습니다 — 위 두 파일명을 현재 구조에 맞게 갱신하십시오."
else
  # 7. 활성 스킬 1곳에만 있으면, .archive 에 같은 이름이 몇 개 있든 그 활성 스킬로 보정돼야
  #    한다. 예전에는 "후보: .archive,.archive,aws" 로 모호 판정되어 exit 1 + FLAGGED 였다
  #    — 실재하지 않는 모호성 때문에 정상적인 근거 기록이 막혔다.
  rm -f "$LOG"
  status=0
  out=$(cd "$TMP" && bash "$RECORD_PROVENANCE" f.tf "$ACTIVE_PLUS_ARCHIVE" "테스트 목적" 2>&1) || status=$?
  if [ "$status" -eq 0 ] && grep -qF "agent:aws/$ACTIVE_PLUS_ARCHIVE" "$LOG" && grep -qF "| SUCCESS" "$LOG"; then
    report "archive-not-counted (활성 1곳이면 .archive 중복과 무관하게 보정)" 0
  else
    report "archive-not-counted (활성 1곳이면 .archive 중복과 무관하게 보정)" 1 "exit=$status out=$out log=$(cat "$LOG" 2>/dev/null)"
  fi

  # 8. .archive 에만 있는 이름은 유일 매치로 통과시키면 안 된다. 예전에는 스킬이 리터럴
  #    ".archive" 로 보정되어 `agent:.archive/<파일>` 이라는 폐기 룰북 근거가 SUCCESS 로
  #    남았다 — 감사 로그가 존재하지 않는 룰을 가리킨다.
  rm -f "$LOG"
  status=0
  out=$(cd "$TMP" && bash "$RECORD_PROVENANCE" g.tf "$ARCHIVE_ONLY" "테스트 목적" 2>&1) || status=$?
  if ! grep -qF "agent:.archive/" "$LOG"; then
    report "archive-only (폐기 룰북을 스킬로 보정하지 않음)" 0
  else
    report "archive-only (폐기 룰북을 스킬로 보정하지 않음)" 1 "exit=$status log=$(cat "$LOG" 2>/dev/null)"
  fi
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
