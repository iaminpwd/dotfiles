#!/usr/bin/env bash
# test-pre-commit-hook.sh
#
# stow/git/.githooks/pre-commit은 bin/*.sh 와 달리 test-coverage-check.sh 게이트 밖에 있다.
# 그 사각지대에서 BIN_REMINDERS 재현 명령 조립 로직이 깨질 수 있다: 사람이 읽을 설명
# 문구 "run.sh (전체 — ...)"를 그대로 커맨드 문자열에 이어붙이면, 출력된 줄을 그대로
# 복붙했을 때 괄호 때문에 셸 문법 오류가 난다. 이 스위트는 그 재현 명령이 실제로
# 유효한 셸 명령인지와, 스테이징된 파일이 디스크에서 사라진 경우를 막는 보안 가드를
# 고정한다.
#
# pre-flight-check.sh 본체(trivy/checkov/terraform 등 무거운 외부 도구 파이프라인)는
# 이 훅의 검증 대상이 아니므로, 픽스처 저장소 안에 exit 0만 하는 스텁으로 교체해
# 훅 자체의 오케스트레이션 로직만 격리해서 검증한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-pre-commit-hook.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
HOOK="$REPO_ROOT/stow/git/.githooks/pre-commit"

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

# BIN_REMINDERS 블록은 "$(basename "$REPO_ROOT")" = "dotfiles" 일 때만 활성화되고,
# 하단의 실제 검증 실행부는 그 조건에서 REPO_ROOT/bin/hooks/pre-flight-check.sh 를
# 우선 사용한다. 그 자리에 exit 0 스텁을 심어두면 무거운 실제 파이프라인을 타지 않고도
# 두 로직을 함께 검증할 수 있다.
FIXTURE_REPO="$TMP/dotfiles"
mkdir -p "$FIXTURE_REPO/bin/hooks"
git -C "$FIXTURE_REPO" init -q
git -C "$FIXTURE_REPO" config user.email "test@example.com"
git -C "$FIXTURE_REPO" config user.name "Test"

cat >"$FIXTURE_REPO/bin/hooks/pre-flight-check.sh" <<'EOF'
#!/usr/bin/env bash
echo "[STUB] pre-flight-check.sh 스텁 실행됨"
exit 0
EOF
chmod +x "$FIXTURE_REPO/bin/hooks/pre-flight-check.sh"
git -C "$FIXTURE_REPO" add bin/hooks/pre-flight-check.sh
# 이 샌드박스는 core.hooksPath가 전역으로 이 저장소의 git/.githooks를 가리키고 있어,
# 훅 격리 없이 커밋하면 픽스처 셋업 중에 실제 훅이 재귀적으로 발동해 출력이 오염된다.
# 테스트 대상 SUT(=아래 run_hook_allow_fail 이 명시적으로 호출하는 $HOOK)와 무관한
# 셋업 커밋이므로 훅을 꺼서 격리한다.
git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "chore: 초기 스텁 커밋"

run_hook_allow_fail() {
  local status=0
  (cd "$FIXTURE_REPO" && bash "$HOOK") >"$TMP/out" 2>&1 || status=$?
  echo "$status"
}

echo "=== pre-commit 훅 오케스트레이션 로직 회귀 테스트 ==="

# 1. bin/hooks/pre-flight-check.sh, bin/linters/container-hardening-gate.sh,
#    bin/hooks/run-suite.sh, bin/lib/tool-probe.sh, bin/utils/stow-backup.sh 를 동시에
#    스테이징하면 BIN_REMINDERS의 모든 case(전용 case 3개 + utils case 1개 + 캐치올 1개)가
#    다 걸린다. 각 재현 명령 줄이 (a) 그대로
#    실행 가능한(파싱 에러 없는) 셸 명령이어야 하고, (b) 실제 dotfiles 저장소에 그 경로가
#    존재해야 한다 — (b)를 놓쳐서 test-run-suite.sh/test-tool-probe-ssot.sh가
#    contexts/pre-flight-check/tests/ 로 잘못 안내되던 버그가 실제로 있었다(고쳐짐).
#    bin/utils/* 는 예전엔 어느 case 에도 안 걸려 아무 안내도 나오지 않는 사각지대였고,
#    이 픽스처가 utils 파일을 하나도 스테이징하지 않아 그 사실이 드러나지 않았다.
mkdir -p "$FIXTURE_REPO/bin/linters" "$FIXTURE_REPO/bin/lib" "$FIXTURE_REPO/bin/utils"
# 초기 커밋과 내용이 완전히 같으면 git diff --cached 에 아예 안 잡혀 이 case가
# 검증되지 않으므로, 한 줄을 더해 실제 스테이징된 변경으로 만든다.
cat >"$FIXTURE_REPO/bin/hooks/pre-flight-check.sh" <<'EOF'
#!/usr/bin/env bash
echo "[STUB] pre-flight-check.sh 스텁 실행됨 (case1)"
exit 0
EOF
echo '#!/usr/bin/env bash' >"$FIXTURE_REPO/bin/linters/container-hardening-gate.sh"
echo '#!/usr/bin/env bash' >"$FIXTURE_REPO/bin/hooks/run-suite.sh"
echo '#!/usr/bin/env bash' >"$FIXTURE_REPO/bin/lib/tool-probe.sh"
echo '#!/usr/bin/env bash' >"$FIXTURE_REPO/bin/utils/stow-backup.sh"
git -C "$FIXTURE_REPO" add bin/hooks/pre-flight-check.sh bin/linters/container-hardening-gate.sh \
  bin/hooks/run-suite.sh bin/lib/tool-probe.sh bin/utils/stow-backup.sh

status=$(run_hook_allow_fail)
OUT="$(cat "$TMP/out")"
REMINDER_LINES=$(grep -E '^\s+bash .*/tests/.*\.sh' "$TMP/out" || true)
REMINDER_COUNT=$(printf '%s\n' "$REMINDER_LINES" | grep -c . || true)

# pre-flight-check.sh 전용(1) + linters/*.sh 캐치올(1) + run-suite.sh 전용(1) +
# tool-probe.sh 전용(2, test-tool-probe-ssot.sh/test-plugin-loop.sh) + utils 캐치올(1)
# = 총 6줄이어야 한다.
if [ "$status" -eq 0 ] && [ "$REMINDER_COUNT" -eq 6 ] && ! grep -qF '(' <<<"$REMINDER_LINES"; then
  # 출력된 재현 명령 줄들을 그대로 셸에 넣어 파싱 에러(예: 괄호로 인한 syntax error)가
  # 없는지 실제로 검증한다. 스텁이 exit 0 이므로 명령 자체는 실행돼도 안전하다.
  PARSE_OK=1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    bash -n <(printf '%s\n' "$line") 2>/dev/null || PARSE_OK=0
  done <<<"$REMINDER_LINES"
  if [ "$PARSE_OK" -eq 1 ]; then
    report "reminder-valid-syntax (재현 명령에 괄호 없이 유효한 셸 문법)" 0
  else
    report "reminder-valid-syntax (재현 명령에 괄호 없이 유효한 셸 문법)" 1 "$REMINDER_LINES"
  fi

  # 재현 명령이 가리키는 경로가 진짜 dotfiles 저장소(REPO_ROOT, 이 테스트 스크립트
  # 자신의 물리적 위치 기준 — FIXTURE_REPO 안이 아니라)에 실제로 존재하는지 검증한다.
  # FIXTURE_REPO 접두사와 뒤에 붙는 " # 설명" 주석을 떼어내고 남는 상대경로로 대조한다.
  PATH_OK=1
  MISSING_PATHS=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    rel="${line#*"$FIXTURE_REPO"/}"
    rel="${rel%%  \#*}"
    if [ ! -e "$REPO_ROOT/$rel" ]; then
      PATH_OK=0
      MISSING_PATHS="$MISSING_PATHS $rel"
    fi
  done <<<"$REMINDER_LINES"
  if [ "$PATH_OK" -eq 1 ]; then
    report "reminder-path-exists (재현 명령이 가리키는 경로가 실제 저장소에 존재)" 0
  else
    report "reminder-path-exists (재현 명령이 가리키는 경로가 실제 저장소에 존재)" 1 "missing:$MISSING_PATHS"
  fi
else
  report "reminder-valid-syntax (재현 명령에 괄호 없이 유효한 셸 문법)" 1 "exit=$status out=$OUT"
  report "reminder-path-exists (재현 명령이 가리키는 경로가 실제 저장소에 존재)" 1 "exit=$status out=$OUT"
fi

git -C "$FIXTURE_REPO" reset -q

# 2. 무관한 파일만 변경하면 BIN_REMINDERS 안내 자체가 나오지 않아야 한다(오탐 방지).
echo "hello" >"$FIXTURE_REPO/README.md"
git -C "$FIXTURE_REPO" add README.md
status=$(run_hook_allow_fail)
if [ "$status" -eq 0 ] && ! grep -qF "bin/ 핵심 검증 로직 변경이 감지되었습니다" "$TMP/out"; then
  report "no-reminder-on-unrelated-change (무관한 변경은 안내 없음)" 0
else
  report "no-reminder-on-unrelated-change (무관한 변경은 안내 없음)" 1 "exit=$status out=$(cat "$TMP/out")"
fi
git -C "$FIXTURE_REPO" reset -q
rm -f "$FIXTURE_REPO/README.md"

# 3. [보안] 스테이징은 됐는데 디스크에서 파일이 사라지고 'git rm --cached'도 안 했으면
#    시크릿 유출 위험 경고와 함께 커밋을 차단해야 한다.
echo "secret-ish content" >"$FIXTURE_REPO/ghost.txt"
git -C "$FIXTURE_REPO" add ghost.txt
rm -f "$FIXTURE_REPO/ghost.txt"
status=$(run_hook_allow_fail)
if [ "$status" -eq 1 ] && grep -qF "디스크에 존재하지 않지만" "$TMP/out"; then
  report "fail-staged-but-deleted (디스크 삭제·스테이징 잔류 차단)" 0
else
  report "fail-staged-but-deleted (디스크 삭제·스테이징 잔류 차단)" 1 "exit=$status out=$(cat "$TMP/out")"
fi
git -C "$FIXTURE_REPO" reset -q -- ghost.txt 2>/dev/null || true

# 4. [보안] 인덱스에는 시크릿이 남아 있는데 워킹트리에서만 지운 경우도 차단해야 한다.
#    스캐너에 "경로"를 넘기면 디스크의 현재(깨끗한) 내용을 읽으므로, git add 후 워킹트리
#    에서만 시크릿을 지우면 스캔은 통과하는데 커밋에는 인덱스의 시크릿이 그대로 들어간다.
#    위 3번 가드는 파일 "삭제"만 막고 이 "수정" 케이스는 못 막았다(실측 재현: 1704바이트
#    개인키가 인덱스에 남은 채 exit 0). 훅이 인덱스 내용을 풀어서 스캔하는지 고정한다.
#    시크릿 픽스처를 저장소에 커밋해 둘 수는 없으므로(우리 자신의 시크릿 스캔에 걸린다)
#    실행 시점에 임시로 키를 만들어 쓴다.
if command -v trufflehog >/dev/null 2>&1 && trufflehog --version >/dev/null 2>&1 &&
  command -v openssl >/dev/null 2>&1; then
  openssl genrsa -out "$FIXTURE_REPO/deploy_key" 2048 2>/dev/null
  # -f: 전역 gitignore 가 키 계열 확장자를 걸러낼 수 있어 강제 스테이징한다.
  git -C "$FIXTURE_REPO" add -f deploy_key
  # 워킹트리에서만 시크릿 제거 (git add 를 다시 하지 않으므로 인덱스에는 그대로 남는다)
  echo "redacted" >"$FIXTURE_REPO/deploy_key"
  status=$(run_hook_allow_fail)
  if [ "$status" -eq 1 ] && grep -qF "시크릿 유출이 발견되어" "$TMP/out"; then
    report "fail-staged-secret-cleaned-in-worktree (인덱스 내용 기준 스캔)" 0
  else
    report "fail-staged-secret-cleaned-in-worktree (인덱스 내용 기준 스캔)" 1 "exit=$status out=$(cat "$TMP/out")"
  fi
  # 5. [보안] `git mv` 로 옮기면서 시크릿을 넣은 경우도 차단해야 한다.
  #    git 은 유사도 50% 이상이면 변경을 R(rename)로 판정하는데, 스테이징 목록 수집이
  #    --diff-filter=ACM 이라 R 이 통째로 빠졌다. 그러면 STAGED_FILES 가 0건이 되어
  #    trufflehog 스캔이 아예 실행되지 않는다 — 위 4번이 "스캔한 바이트와 커밋될 바이트를
  #    일치시킨다"고 맞춰 둔 전제가 목록 단계에서 깨져 있었다(실측: rename 커밋에서 훅
  #    출력이 한 줄도 없었고, 같은 내용 변경을 rename 없이 하면 스캔이 정상 실행됐다).
  #    유사도가 임계값 위로 유지되도록 원본을 채운 뒤 rename + 키 추가로 재현한다
  #    (전체를 키로 갈아치우면 유사도가 낮아 git 이 D+A 로 분해해 이 경로를 안 탄다).
  for i in $(seq 1 200); do echo "filler line $i for rename similarity"; done >"$FIXTURE_REPO/notes.txt"
  git -C "$FIXTURE_REPO" add notes.txt
  git -C "$FIXTURE_REPO" -c core.hooksPath=/dev/null commit -q -m "chore: 이름 변경 픽스처 추가"
  git -C "$FIXTURE_REPO" mv notes.txt notes-renamed.txt
  openssl genrsa -out "$TMP/rename_key" 2048 2>/dev/null
  # idempotency:bypass (임시 픽스처에 대한 1회성 기록이라 상태 검증 불필요)
  cat "$TMP/rename_key" >>"$FIXTURE_REPO/notes-renamed.txt"
  git -C "$FIXTURE_REPO" add -f notes-renamed.txt
  # 실제로 R 로 잡히는 상태인지 먼저 확인한다. D+A 로 분해됐다면 이 케이스는 의도한
  # 사각지대를 재현하지 못한 것이므로, 통과하더라도 의미가 없다.
  if git -C "$FIXTURE_REPO" diff --cached --name-status | grep -q '^R'; then
    status=$(run_hook_allow_fail)
    if [ "$status" -eq 1 ] && grep -qF "시크릿 유출이 발견되어" "$TMP/out"; then
      report "fail-renamed-file-with-secret (git mv 한 파일도 시크릿 스캔 대상)" 0
    else
      report "fail-renamed-file-with-secret (git mv 한 파일도 시크릿 스캔 대상)" 1 "exit=$status out=$(cat "$TMP/out")"
    fi
  else
    report "fail-renamed-file-with-secret (git mv 한 파일도 시크릿 스캔 대상)" 1 "픽스처가 rename(R)으로 잡히지 않아 사각지대를 재현하지 못했습니다"
  fi
  git -C "$FIXTURE_REPO" reset -q
  rm -f "$FIXTURE_REPO/notes-renamed.txt" "$TMP/rename_key"
  git -C "$FIXTURE_REPO" checkout -q -- notes.txt 2>/dev/null || true

  git -C "$FIXTURE_REPO" reset -q
  rm -f "$FIXTURE_REPO/deploy_key"
else
  echo "  SKIP  fail-staged-secret-cleaned-in-worktree (trufflehog 또는 openssl 미설치)"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
