#!/usr/bin/env bash
# CI가 최종 워킹트리뿐 아니라 PR/push의 Git 커밋 범위 자체를 시크릿 스캔하는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
# shellcheck source=tests/lib/parallel-pair.sh
source "$ROOT/tests/lib/parallel-pair.sh"
SCAN="$ROOT/.github/scripts/secret-history-scan.sh"
WORKFLOW="$ROOT/.github/workflows/ci.yml"

if [ ! -f "$SCAN" ]; then
  echo "FAIL: Git 히스토리 시크릿 스캔 스크립트가 없습니다: $SCAN"
  exit 1
fi
if ! grep -Fq 'bash .github/scripts/secret-history-scan.sh' "$WORKFLOW"; then
  echo "FAIL: CI가 Git 히스토리 시크릿 스캔을 호출하지 않습니다"
  exit 1
fi

if ! command -v trufflehog >/dev/null 2>&1 || ! trufflehog --version >/dev/null 2>&1 ||
  ! command -v openssl >/dev/null 2>&1; then
  echo "[WARNING] SKIP functional secret-history scan — trufflehog 또는 openssl 미설치"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name Test

printf 'base\n' >"$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" -c core.hooksPath=/dev/null commit -q -m "chore: base"
BASE=$(git -C "$REPO" rev-parse HEAD)

# 저장소 자체에는 키 픽스처를 두지 않는다. 실행 시 임시 저장소에만 생성하고,
# 다음 커밋에서 삭제해 "최종 트리는 깨끗하지만 히스토리에는 남은" 상태를 재현한다.
openssl genrsa -out "$REPO/leaked-key.pem" 2048 2>/dev/null
git -C "$REPO" add -f leaked-key.pem
git -C "$REPO" -c core.hooksPath=/dev/null commit -q -m "test: temporary secret"
git -C "$REPO" rm -q leaked-key.pem
git -C "$REPO" -c core.hooksPath=/dev/null commit -q -m "test: remove secret"
HEAD=$(git -C "$REPO" rev-parse HEAD)

run_scan() {
  local event=$1
  shift
  (
    cd "$REPO"
    env EVENT_NAME="$event" "$@" bash "$SCAN"
  )
}

# 두 검사는 같은 불변 Git 커밋 범위를 PR/push 이벤트로 읽기만 한다.
# 쓰기/임시 로그를 공유하지 않으므로 기존 검증된 parallel-pair.sh로 병행한다.
# shellcheck disable=SC2034 # parallel_pair_run 이 nameref로 읽음
CMD_PR=(run_scan pull_request BASE_SHA="$BASE" HEAD_SHA="$HEAD")
# shellcheck disable=SC2034
CMD_PUSH=(run_scan push BEFORE_SHA="$BASE" AFTER_SHA="$HEAD")
pr_status=0
push_status=0
parallel_pair_run CMD_PR CMD_PUSH pr_status push_status "$TMP/pr-bad.out" "$TMP/push-bad.out"

if [ "$pr_status" -eq 0 ]; then
  echo "FAIL: PR 범위의 중간 커밋 시크릿이 차단되지 않았습니다"
  cat "$TMP/pr-bad.out"
  exit 1
fi
echo "PASS: PR 커밋 범위의 삭제된 시크릿도 차단"

if [ "$push_status" -eq 0 ]; then
  echo "FAIL: push 범위의 중간 커밋 시크릿이 차단되지 않았습니다"
  cat "$TMP/push-bad.out"
  exit 1
fi
echo "PASS: push 커밋 범위의 삭제된 시크릿도 차단"

# 삭제 커밋 이후의 깨끗한 새 커밋만 범위로 주면 과거 시크릿 때문에 영구 차단되면 안 된다.
CLEAN_BASE="$HEAD"
# idempotency:bypass (매 실행마다 새 mktemp 저장소에 후속 커밋을 만드는 1회성 fixture mutation)
printf 'clean\n' >>"$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" -c core.hooksPath=/dev/null commit -q -m "test: clean change"
CLEAN_HEAD=$(git -C "$REPO" rev-parse HEAD)

# 깨끗한 범위와 새 ref 전체 스캔은 동일한 고정 커밋을 독립적으로 읽는다.
# shellcheck disable=SC2034 # parallel_pair_run 이 nameref로 읽음
CMD_CLEAN=(run_scan pull_request BASE_SHA="$CLEAN_BASE" HEAD_SHA="$CLEAN_HEAD")
# shellcheck disable=SC2034
CMD_NEWREF=(run_scan push BEFORE_SHA=0000000000000000000000000000000000000000 AFTER_SHA="$CLEAN_HEAD")
clean_status=0
newref_status=0
parallel_pair_run CMD_CLEAN CMD_NEWREF clean_status newref_status "$TMP/clean.out" "$TMP/newref.out"

if [ "$clean_status" -ne 0 ]; then
  echo "FAIL: 깨끗한 신규 범위가 과거 히스토리 때문에 차단되었습니다"
  cat "$TMP/clean.out"
  exit 1
fi
echo "PASS: 검사 범위 밖의 과거 시크릿은 재차단하지 않음"

# 새 ref의 첫 push는 BEFORE_SHA=0이며 한 번에 여러 커밋을 포함할 수 있다.
# 첫 커밋과 중간 커밋의 비밀이 마지막 트리에서 삭제됐어도 전체 이력을 검사해야 한다.
# 기존 구현은 head^를 기준으로 삼아 마지막 커밋 한 개만 검사하므로 놓친다.
if [ "$newref_status" -eq 0 ]; then
  echo "FAIL: 새 ref 첫 push에서 마지막 커밋 이전의 삭제된 시크릿을 놓쳤습니다"
  cat "$TMP/newref.out"
  exit 1
fi
echo "PASS: 새 ref 첫 push는 전체 도달 가능 이력의 시크릿을 차단"
