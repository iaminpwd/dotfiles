#!/usr/bin/env bash
# test-record-provenance.sh
#
# record-provenance.sh는 rule_source가 "<스킬>/파일명" 형태가 아닐 때 contexts/ 전체에서 자동으로
# 스킬을 보정하는데, 동일 파일명이 여러 스킬에 존재하면 AMBIGUOUS로 표시하고 exit 1을
# 내야 한다(감사 로그 신뢰성의 핵심). 또한 agent-edits-hook.sh가 남긴 미확정("-") 라인이
# 있으면 새 줄을 추가하는 대신 그 자리를 SUCCESS/FLAGGED로 보강(overwrite)하는 병합 로직도
# 있다. 이 두 판정/병합 로직이 깨지면 근거 없는 SUCCESS가 찍히거나 로그가 중복될 수 있으므로
# 실제 contexts/와 최소 합성 코퍼스를 각각 사용해 고정한다.
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
out=$(cd "$TMP" && bash "$RECORD_PROVENANCE" a.tf "dotfiles/010-core.md" "테스트 목적" 2>&1) || status=$?
if [ "$status" -eq 0 ] && grep -qF "agent:dotfiles/010-core.md" "$LOG" && grep -qF "| SUCCESS" "$LOG"; then
  report "skill-qualified (그대로 SUCCESS)" 0
else
  report "skill-qualified (그대로 SUCCESS)" 1 "exit=$status out=$out log=$(cat "$LOG" 2>/dev/null)"
fi

# 2. 유일 basename 자동 보정은 실제 prompt corpus의 특정 파일명이 남아 있는지에
#    의존하지 않는다. 최소 합성 코퍼스로 resolve_source 알고리즘 자체를 고정한다.
UNIQUE_FAKE="$TMP/unique-repo"
mkdir -p "$UNIQUE_FAKE/bin/utils" "$UNIQUE_FAKE/bin/lib" \
  "$UNIQUE_FAKE/contexts/alpha/references" "$UNIQUE_FAKE/work"
cp "$RECORD_PROVENANCE" "$UNIQUE_FAKE/bin/utils/"
cp "$REPO_ROOT/bin/lib/git-relpath.sh" "$UNIQUE_FAKE/bin/lib/"
: >"$UNIQUE_FAKE/contexts/alpha/references/unique-rule.md"
UNIQUE_RP="$UNIQUE_FAKE/bin/utils/record-provenance.sh"
UNIQUE_LOG="$UNIQUE_FAKE/work/.agent-state/edits.log"

status=0
out=$(cd "$UNIQUE_FAKE/work" && bash "$UNIQUE_RP" b.tf "unique-rule.md" "테스트 목적" 2>&1) || status=$?
if [ "$status" -eq 0 ] && grep -qF "agent:alpha/unique-rule.md" "$UNIQUE_LOG" && grep -qF "| SUCCESS" "$UNIQUE_LOG"; then
  report "unique-basename (자동 스킬 보정)" 0
else
  report "unique-basename (자동 스킬 보정)" 1 "exit=$status out=$out log=$(cat "$UNIQUE_LOG" 2>/dev/null)"
fi

# 2a. <skill>/<filename> 형식으로 이미 qualified된 입력도 실제 활성 contexts 아래에
# 존재하는 근거인지 검증해야 한다. slash가 있다는 이유만으로 없는 파일을 SUCCESS로
# 기록하면 감사 로그가 존재하지 않는 룰을 정당한 근거처럼 남긴다.
rm -f "$UNIQUE_LOG"
status=0
out=$(cd "$UNIQUE_FAKE/work" && bash "$UNIQUE_RP" missing.tf "alpha/missing-rule.md" "존재 검증" 2>&1) || status=$?
if [ "$status" -eq 1 ] &&
  grep -qF "MISSING(alpha/missing-rule.md)" "$UNIQUE_LOG" &&
  grep -qF "| FLAGGED" "$UNIQUE_LOG" &&
  grep -qF "존재하지 않는 rule_source" <<<"$out"; then
  report "qualified-missing-source (없는 근거는 FLAGGED + exit 1)" 0
else
  report "qualified-missing-source (없는 근거는 FLAGGED + exit 1)" 1 "exit=$status out=$out log=$(cat "$UNIQUE_LOG" 2>/dev/null)"
fi

# 3~4. 모호성 판정은 실제 코퍼스에서 우연히 같은 basename이 남아 있는지에 의존하지
# 않는다. 두 활성 스킬에 같은 파일명을 둔 최소 코퍼스를 합성해 알고리즘 자체를 고정한다.
AMB_FAKE="$TMP/ambiguous-repo"
mkdir -p "$AMB_FAKE/bin/utils" "$AMB_FAKE/bin/lib" \
  "$AMB_FAKE/contexts/alpha/references" "$AMB_FAKE/contexts/beta/references" "$AMB_FAKE/work"
cp "$RECORD_PROVENANCE" "$AMB_FAKE/bin/utils/"
cp "$REPO_ROOT/bin/lib/git-relpath.sh" "$AMB_FAKE/bin/lib/"
: >"$AMB_FAKE/contexts/alpha/references/duplicate-rule.md"
: >"$AMB_FAKE/contexts/beta/references/duplicate-rule.md"
: >"$AMB_FAKE/contexts/alpha/references/unique-rule.md"
AMB_RP="$AMB_FAKE/bin/utils/record-provenance.sh"
AMB_LOG="$AMB_FAKE/work/.agent-state/edits.log"

# 3. 여러 활성 스킬에 동일 파일명이 있으면 FLAGGED + exit 1.
rm -f "$AMB_LOG"
status=0
out=$(cd "$AMB_FAKE/work" && bash "$AMB_RP" c.tf "duplicate-rule.md" "테스트 목적" 2>&1) || status=$?
if [ "$status" -eq 1 ] && grep -qF "AMBIGUOUS(" "$AMB_LOG" && grep -qF "| FLAGGED" "$AMB_LOG" && grep -qF "여러 스킬에" <<<"$out"; then
  report "ambiguous-basename (AMBIGUOUS + FLAGGED + exit 1)" 0
else
  report "ambiguous-basename (AMBIGUOUS + FLAGGED + exit 1)" 1 "exit=$status out=$out log=$(cat "$AMB_LOG" 2>/dev/null)"
fi

# 4. 콤마로 여러 rule_source를 넘기면 하나라도 모호하면 전체가 FAILED(exit 1)여야 한다.
rm -f "$AMB_LOG"
status=0
out=$(cd "$AMB_FAKE/work" && bash "$AMB_RP" d.tf "alpha/unique-rule.md,duplicate-rule.md" "테스트 목적" 2>&1) || status=$?
if [ "$status" -eq 1 ] && grep -qF "alpha/unique-rule.md,AMBIGUOUS(" "$AMB_LOG"; then
  report "multi-source (일부 모호하면 전체 FAILED)" 0
else
  report "multi-source (일부 모호하면 전체 FAILED)" 1 "exit=$status out=$out log=$(cat "$AMB_LOG" 2>/dev/null)"
fi

# 5. agent-edits-hook.sh가 남긴 미확정 라인("- " 목적, 5번째 필드 SUCCESS 아님)이 있으면
#    새 줄을 추가하는 대신 그 자리를 보강(overwrite)해야 한다 -> 총 줄 수 1 유지.
rm -f "$LOG"
mkdir -p "$(dirname "$LOG")"
echo "2026-01-01T00:00:00+00:00 | e.tf | hook:Edit | - | OK" >"$LOG"
status=0
out=$(cd "$TMP" && bash "$RECORD_PROVENANCE" e.tf "dotfiles/010-core.md" "테스트 목적" 2>&1) || status=$?
LINES=$(wc -l <"$LOG")
if [ "$status" -eq 0 ] && [ "$LINES" -eq 1 ] && grep -qF "agent:dotfiles/010-core.md" "$LOG" && grep -qF "| SUCCESS" "$LOG"; then
  report "미확정 라인 보강 (append 대신 overwrite, 1줄 유지)" 0
else
  report "미확정 라인 보강 (append 대신 overwrite, 1줄 유지)" 1 "exit=$status lines=$LINES log=$(cat "$LOG" 2>/dev/null)"
fi

# 6. 이미 SUCCESS로 확정된 라인은 더 이상 보강 대상이 아니므로, 재호출 시 새 줄이 append되어야 한다.
status=0
out=$(cd "$TMP" && bash "$RECORD_PROVENANCE" e.tf "dotfiles/010-core.md" "두 번째 목적" 2>&1) || status=$?
LINES=$(wc -l <"$LOG")
if [ "$status" -eq 0 ] && [ "$LINES" -eq 2 ]; then
  report "확정된 SUCCESS 라인 이후 재호출 (append)" 0
else
  report "확정된 SUCCESS 라인 이후 재호출 (append)" 1 "exit=$status lines=$LINES log=$(cat "$LOG" 2>/dev/null)"
fi

# 6a. 훅의 ERROR 라인은 실패한 편집 시도라는 독립 감사 이력이다. provenance 보강은
# 성공 편집의 더미 OK 또는 이전 FLAGGED만 갱신해야 하며 ERROR를 SUCCESS로 덮어쓰면 안 된다.
rm -f "$LOG"
echo "2026-01-01T00:00:00+00:00 | error.tf | hook:Edit | - | ERROR:permission denied" >"$LOG"
status=0
out=$(cd "$TMP" && bash "$RECORD_PROVENANCE" error.tf "dotfiles/010-core.md" "후속 정상 작업" 2>&1) || status=$?
LINES=$(wc -l <"$LOG")
if [ "$status" -eq 0 ] &&
  [ "$LINES" -eq 2 ] &&
  grep -qF "hook:Edit | - | ERROR:permission denied" "$LOG" &&
  grep -qF "agent:dotfiles/010-core.md | 후속 정상 작업 | SUCCESS" "$LOG"; then
  report "hook-error-preserved (실패 이력 보존 + provenance 별도 append)" 0
else
  report "hook-error-preserved (실패 이력 보존 + provenance 별도 append)" 1 "exit=$status lines=$LINES log=$(cat "$LOG" 2>/dev/null)"
fi

# 6b. 보강 임시파일은 예측 가능한 고정 경로를 쓰면 안 된다. 공격자/다른 프로세스가
# 그 경로를 symlink로 선점하면 awk 리다이렉션이 임의 파일을 덮어쓰고, 이어지는 mv가
# edits.log 자체를 그 symlink로 바꿀 수 있다. 임시파일은 mktemp로 안전하게 생성해야 한다.
rm -f "$LOG"
mkdir -p "$(dirname "$LOG")"
echo "2026-01-01T00:00:00+00:00 | temp-race.tf | hook:Edit | - | OK" >"$LOG"
VICTIM="$TMP/victim.txt"
printf 'DO_NOT_TOUCH\n' >"$VICTIM"
PREDICTABLE_TMP="$LOG.tmp.$"
rm -f "$PREDICTABLE_TMP"
ln -s "$VICTIM" "$PREDICTABLE_TMP"

status=0
out=$(cd "$TMP" && bash "$RECORD_PROVENANCE" temp-race.tf "dotfiles/010-core.md" "임시파일 안전성" 2>&1) || status=$?
if [ "$status" -eq 0 ] &&
  grep -qxF "DO_NOT_TOUCH" "$VICTIM" &&
  [ ! -L "$LOG" ] &&
  grep -qF "agent:dotfiles/010-core.md | 임시파일 안전성 | SUCCESS" "$LOG"; then
  report "secure-tempfile (선점 symlink 무시 + 감사 로그 정상 보강)" 0
else
  report "secure-tempfile (선점 symlink 무시 + 감사 로그 정상 보강)" 1 "exit=$status victim=$(cat "$VICTIM" 2>/dev/null) log_link=$(test -L "$LOG" && echo yes || echo no)"
fi
rm -f "$LOG" "$PREDICTABLE_TMP"

# 6c. 어떤 룰북과도 매칭되지 않는 이름은 입력값을 그대로 쓰고 정상 종료해야 한다.
#     문서화된 동작인데 케이스가 없었다. 스킬 보정 find 가 0건일 때의 경로라,
#     resolve_source 안에서 카운트를 세는 grep 이 무매치로 죽으면 여기서 드러난다.
rm -f "$LOG"
status=0
out=$(cd "$TMP" && bash "$RECORD_PROVENANCE" h.tf "매칭되지-않는-이름.md" "테스트 목적" 2>&1) || status=$?
if [ "$status" -eq 0 ] && grep -qF "agent:매칭되지-않는-이름.md" "$LOG" && grep -qF "| SUCCESS" "$LOG"; then
  report "no-match (입력값 그대로 SUCCESS)" 0
else
  report "no-match (입력값 그대로 SUCCESS)" 1 "exit=$status out=$out log=$(cat "$LOG" 2>/dev/null)"
fi

# -----------------------------------------------------------------------------
# 7~8. contexts/ 의 숨김 디렉토리가 스킬 보정 후보에 섞이면 안 된다.
#
# 스킬 보정 find 가 숨김 디렉토리를 함께 세면 양방향으로 깨진다 — 둘 다 폐기 스킬
# 보관소(contexts/.archive)가 실제 코퍼스에 있던 시절 실측으로 재현하고 고친 결함이다.
# 그 보관소를 지운 뒤(내용은 git 히스토리에 그대로 남아 있다) 남은 숨김 디렉토리는
# .shared 뿐인데 거기엔 룰북이 없어 실물로는 재현할 수 없다. 판정 로직 자체는 그대로
# 살아 있으므로 최소 코퍼스를 합성해 고정한다. 이 스위트는 basename 해석 알고리즘을
# prompt corpus의 우연한 파일명에 결합하지 않기 위해 unique/ambiguous/hidden 케이스를 합성 코퍼스로 고정한다.
#
# record-provenance.sh 는 CONTEXTS_DIR 를 "자기 실경로의 상위 두 단계"로 계산하므로
# (환경변수로 못 바꾼다) 합성 코퍼스를 태우려면 스크립트와 그 의존 lib 을 가짜 트리에
# 복사해 그쪽 사본을 실행해야 한다. 심볼릭 링크는 readlink -f 가 원본으로 되돌리므로 안 된다.
FAKE="$TMP/fake-repo"
mkdir -p "$FAKE/bin/utils" "$FAKE/bin/lib" \
  "$FAKE/contexts/aws/references" "$FAKE/contexts/.hidden/references" "$FAKE/work"
cp "$RECORD_PROVENANCE" "$FAKE/bin/utils/"
cp "$REPO_ROOT/bin/lib/git-relpath.sh" "$FAKE/bin/lib/"
FAKE_RP="$FAKE/bin/utils/record-provenance.sh"
FAKE_LOG="$FAKE/work/.agent-state/edits.log"

DUP_NAME="080-database-standard.md"      # 활성 1곳 + 숨김 1곳
HIDDEN_ONLY="026-networking-standard.md" # 숨김에만 존재
: >"$FAKE/contexts/aws/references/$DUP_NAME"
: >"$FAKE/contexts/.hidden/references/$DUP_NAME"
: >"$FAKE/contexts/.hidden/references/$HIDDEN_ONLY"

# 7. 활성 스킬 1곳에만 있으면, 숨김 디렉토리에 같은 이름이 몇 개 있든 그 활성 스킬로
#    보정돼야 한다. 예전에는 "후보: .archive,.archive,aws" 로 모호 판정되어 exit 1 +
#    FLAGGED 였다 — 실재하지 않는 모호성 때문에 정상적인 근거 기록이 막혔다.
rm -f "$FAKE_LOG"
status=0
out=$(cd "$FAKE/work" && bash "$FAKE_RP" f.tf "$DUP_NAME" "테스트 목적" 2>&1) || status=$?
if [ "$status" -eq 0 ] && grep -qF "agent:aws/$DUP_NAME" "$FAKE_LOG" && grep -qF "| SUCCESS" "$FAKE_LOG"; then
  report "hidden-not-counted (활성 1곳이면 숨김 중복과 무관하게 보정)" 0
else
  report "hidden-not-counted (활성 1곳이면 숨김 중복과 무관하게 보정)" 1 "exit=$status out=$out log=$(cat "$FAKE_LOG" 2>/dev/null)"
fi

# 8. 숨김 디렉토리에만 있는 이름은 유일 매치로 통과시키면 안 된다. 예전에는 스킬이 리터럴
#    ".archive" 로 보정되어 `agent:.archive/<파일>` 이라는 폐기 룰북 근거가 SUCCESS 로
#    남았다 — 감사 로그가 존재하지 않는 룰을 가리킨다.
rm -f "$FAKE_LOG"
status=0
out=$(cd "$FAKE/work" && bash "$FAKE_RP" g.tf "$HIDDEN_ONLY" "테스트 목적" 2>&1) || status=$?
if ! grep -qF "agent:.hidden/" "$FAKE_LOG"; then
  report "hidden-only (숨김 디렉토리를 스킬로 보정하지 않음)" 0
else
  report "hidden-only (숨김 디렉토리를 스킬로 보정하지 않음)" 1 "exit=$status log=$(cat "$FAKE_LOG" 2>/dev/null)"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
