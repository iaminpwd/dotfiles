#!/usr/bin/env bash
# test-git-relpath.sh
#
# bin/lib/git-relpath.sh 는 agent-edits-hook.sh(자동 훅)와 record-provenance.sh(수동 CLI)가 공유하는
# realpath+git-root 조회 SSOT다. 소비자가 각자 옛 인라인 로직을 되살리면 두 스크립트의
# REL 계산 기준이 다시 갈라져 record-provenance.sh의 "미확정 라인 보강" 매칭이 조용히 깨질 수 있다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-git-relpath.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
LIB="$REPO_ROOT/bin/lib/git-relpath.sh"

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

echo "--- git-relpath.sh 공용 라이브러리 (SSOT) ---"

# 1. 라이브러리 계약: source 하면 resolve_target_and_git_root 함수가 정의되어야 한다.
code=0
bash -c 'set -euo pipefail
  source "$1"
  declare -F resolve_target_and_git_root >/dev/null' _ "$LIB" || code=$?
if [ "$code" -eq 0 ]; then
  report "resolve_target_and_git_root 함수 제공" 0
else
  report "resolve_target_and_git_root 함수 제공" 1 "exit=$code"
fi

# 2. git 저장소 안의 파일이면 해당 저장소 루트를 반환해야 한다.
FIXTURE_REPO="$TMP/fixture-repo"
mkdir -p "$FIXTURE_REPO/sub"
git -C "$FIXTURE_REPO" init -q
echo hi >"$FIXTURE_REPO/sub/file.txt"

out=$(bash -c 'source "$1"; resolve_target_and_git_root "$2"' _ "$LIB" "$FIXTURE_REPO/sub/file.txt")
IFS=$'\t' read -r resolved git_root <<<"$out"
if [ "$resolved" = "$(readlink -f "$FIXTURE_REPO/sub/file.txt")" ] && [ "$git_root" = "$(readlink -f "$FIXTURE_REPO")" ]; then
  report "git 저장소 내부 파일 -> 저장소 루트 반환" 0
else
  report "git 저장소 내부 파일 -> 저장소 루트 반환" 1 "resolved=$resolved git_root=$git_root"
fi

# 3. git 저장소 밖의 파일이면 두 번째 필드(git_root)가 빈 문자열이어야 한다.
NO_GIT="$TMP/no-git"
mkdir -p "$NO_GIT"
echo hi >"$NO_GIT/lone.txt"

out=$(bash -c 'source "$1"; resolve_target_and_git_root "$2"' _ "$LIB" "$NO_GIT/lone.txt")
IFS=$'\t' read -r resolved git_root <<<"$out"
if [ "$resolved" = "$(readlink -f "$NO_GIT/lone.txt")" ] && [ -z "$git_root" ]; then
  report "git 저장소 밖 파일 -> git_root 빈 문자열" 0
else
  report "git 저장소 밖 파일 -> git_root 빈 문자열" 1 "resolved=$resolved git_root='$git_root'"
fi

# 4. 심볼릭 링크를 거쳐 들어온 경로는 실경로로 정규화되어야 한다.
#
# 이 라이브러리의 존재 이유가 바로 이 정규화인데(헤더 주석: "모노레포 환경 통합 기록 및
# 심볼릭 링크 경로 불일치 방지"), 위 2·3번은 mktemp 가 만든 "이미 정규화된" 경로만 넘겨서
# readlink -f 가 no-op 이었다 — 즉 resolved="$input" 로 바꿔도 네 케이스가 전부 통과했다
# (뮤테이션 테스트로 실측). 계약이 있는데 그것을 깨뜨려도 아무도 못 잡는 상태였다.
#
# 정규화가 빠지면 무엇이 깨지는지가 이 케이스의 요점이다. git_root 는 어느 쪽이든 실경로
# (.../real)로 나오는데 resolved 만 링크 경로(.../linkdir/...)로 남으면, 소비자의
# "root 가 target 을 포함하는가" 판정이 실패해 agent-edits-hook.sh 가 저장소 루트가 아닌
# 파일 자신의 디렉토리로 로그를 재라우팅한다 — 감사 로그가 엉뚱한 곳에 쌓인다.
LINK_BASE="$TMP/symlink-case"
mkdir -p "$LINK_BASE/real/sub"
git -C "$LINK_BASE/real" init -q
echo hi >"$LINK_BASE/real/sub/file.txt"
ln -s real "$LINK_BASE/linkdir"

out=$(bash -c 'source "$1"; resolve_target_and_git_root "$2"' _ "$LIB" "$LINK_BASE/linkdir/sub/file.txt")
IFS=$'\t' read -r resolved git_root <<<"$out"
EXPECTED_REAL="$(readlink -f "$LINK_BASE/real/sub/file.txt")"
if [ "$resolved" = "$EXPECTED_REAL" ]; then
  report "심볼릭 링크 경로 -> 실경로로 정규화" 0
else
  report "심볼릭 링크 경로 -> 실경로로 정규화" 1 "기대 '$EXPECTED_REAL' / 실제 '$resolved'"
fi

# 정규화된 resolved 는 반드시 같이 반환된 git_root 아래에 있어야 한다. 소비자의 컨테인먼트
# 판정이 이 불변식에 기대고 있으므로 함께 고정한다.
case "$resolved" in
"$git_root"/*) report "정규화 결과가 git_root 하위에 위치(컨테인먼트 불변식)" 0 ;;
*) report "정규화 결과가 git_root 하위에 위치(컨테인먼트 불변식)" 1 "resolved=$resolved git_root=$git_root" ;;
esac

# 5. 소비자(agent-edits-hook.sh, record-provenance.sh)가 옛 인라인 로직을 되살리지 않았는지 확인한다.
CONSUMERS=(
  "$REPO_ROOT/bin/hooks/agent-edits-hook.sh"
  "$REPO_ROOT/bin/utils/record-provenance.sh"
)
dup=0
for consumer in "${CONSUMERS[@]}"; do
  if ! grep -qF "source" "$consumer" || ! grep -qF "git-relpath.sh" "$consumer"; then
    dup=1
  fi
  grep -qE 'rev-parse --show-toplevel' "$consumer" && dup=1
done
if [ "$dup" -eq 0 ]; then
  report "소비자가 공용 라이브러리를 실제로 source하고 인라인 복제를 안 함" 0
else
  report "소비자가 공용 라이브러리를 실제로 source하고 인라인 복제를 안 함" 1 "복제본이 되살아났거나 source가 빠졌습니다"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
