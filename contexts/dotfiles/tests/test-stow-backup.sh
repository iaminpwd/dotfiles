#!/usr/bin/env bash
# test-stow-backup.sh
#
# stow-backup.sh는 stow가 심볼릭 링크를 걸기 전, HOME에 이미 존재하는 실제 파일을 백업으로
# 치워주는 안전장치다. "이미 stow와 동일한 상대경로 심볼릭 링크면 건드리지 않는다"는 조건이
# 깨지면, 정상적으로 연결된 기존 심볼릭 링크를 불필요하게 백업 파일로 바꿔버리거나(멱등성
# 위반), 반대로 진짜 충돌 파일을 못 옮겨 stow가 실패하게 된다.
#
# GNU Stow는 자기가 만드는 "상대경로" 심볼릭 링크만 소유로 인식하고, 절대경로 심볼릭
# 링크는 설령 같은 파일을 가리켜도 foreign으로 보고 -R을 거부한다(실측: 이전 버전
# bootstrap.sh가 절대경로로 ln -sfn 해두었던 mise/.config/mise/config.toml에서 재현).
# 그래서 "이미 심볼릭 링크인가"가 아니라 "상대경로 형식인가"가 진짜 판정 기준이다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-stow-backup.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
BACKUP="$REPO_ROOT/bin/utils/stow-backup.sh"

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

echo "=== stow-backup.sh 충돌 파일 백업 로직 회귀 테스트 ==="

# 1. fail-real-conflict: HOME에 이미 다른 내용의 실제 파일이 있으면 백업으로 치워야 한다.
CASE1="$TMP/case1"
mkdir -p "$CASE1/dotfiles/pkg" "$CASE1/home"
echo "dotfiles 버전" >"$CASE1/dotfiles/pkg/.conflictrc"
echo "홈에 이미 있던 버전" >"$CASE1/home/.conflictrc"

bash "$BACKUP" "pkg" "$CASE1/dotfiles" "$CASE1/home"

BACKUPS=("$CASE1/home"/.conflictrc.backup.*)
if [ ! -e "$CASE1/home/.conflictrc" ] && [ -f "${BACKUPS[0]}" ] && grep -qF "홈에 이미 있던 버전" "${BACKUPS[0]}"; then
  report "fail-real-conflict (실제 파일이면 백업으로 이동)" 0
else
  report "fail-real-conflict (실제 파일이면 백업으로 이동)" 1 "$(ls -la "$CASE1/home" 2>&1)"
fi

# 2. ok-already-linked: HOME의 파일이 이미 stow와 동일한 "상대경로" 심볼릭 링크로 dotfiles
#    소스를 가리키면 건드리지 않는다.
CASE2="$TMP/case2"
mkdir -p "$CASE2/dotfiles/pkg" "$CASE2/home"
echo "dotfiles 버전" >"$CASE2/dotfiles/pkg/.linkedrc"
ln -s "../dotfiles/pkg/.linkedrc" "$CASE2/home/.linkedrc"

bash "$BACKUP" "pkg" "$CASE2/dotfiles" "$CASE2/home"

if [ -L "$CASE2/home/.linkedrc" ] && [ "$(readlink "$CASE2/home/.linkedrc")" = "../dotfiles/pkg/.linkedrc" ]; then
  report "ok-already-linked (stow와 동일한 상대경로 링크면 그대로 유지)" 0
else
  report "ok-already-linked (stow와 동일한 상대경로 링크면 그대로 유지)" 1 "$(ls -la "$CASE2/home" 2>&1)"
fi

# 2b. fail-foreign-absolute-link: 같은 파일을 가리켜도 절대경로 심볼릭 링크는 GNU Stow가
#     "not owned by stow"로 보고 -R을 거부하므로, stow가 자기 형식으로 다시 만들 수 있게
#     미리 백업으로 치워야 한다.
CASE2B="$TMP/case2b"
mkdir -p "$CASE2B/dotfiles/pkg" "$CASE2B/home"
echo "dotfiles 버전" >"$CASE2B/dotfiles/pkg/.absrc"
ln -s "$CASE2B/dotfiles/pkg/.absrc" "$CASE2B/home/.absrc"

bash "$BACKUP" "pkg" "$CASE2B/dotfiles" "$CASE2B/home"

ABS_BACKUPS=("$CASE2B/home"/.absrc.backup.*)
if [ ! -e "$CASE2B/home/.absrc" ] && [ -L "${ABS_BACKUPS[0]}" ]; then
  report "fail-foreign-absolute-link (절대경로 링크는 같은 대상이어도 백업)" 0
else
  report "fail-foreign-absolute-link (절대경로 링크는 같은 대상이어도 백업)" 1 "$(ls -la "$CASE2B/home" 2>&1)"
fi

# 2c. fail-stale-relative-link: 패키지 디렉토리가 옮겨져(예: zsh/ -> stow/zsh/) 상대경로
#     링크가 끊어진 경우도, "상대경로면 무조건 stow 소유로 본다"는 예전 로직으론 놓치고
#     GNU Stow가 "not owned by stow"로 -R을 거부한다(실측: stow/ 이관 직후 재현).
CASE2C="$TMP/case2c"
mkdir -p "$CASE2C/dotfiles/pkg" "$CASE2C/home"
echo "dotfiles 버전" >"$CASE2C/dotfiles/pkg/.movedrc"
ln -s "../old-location/pkg/.movedrc" "$CASE2C/home/.movedrc"

bash "$BACKUP" "pkg" "$CASE2C/dotfiles" "$CASE2C/home"

STALE_BACKUPS=("$CASE2C/home"/.movedrc.backup.*)
if [ ! -e "$CASE2C/home/.movedrc" ] && [ -L "${STALE_BACKUPS[0]}" ]; then
  report "fail-stale-relative-link (패키지 이동으로 끊어진 상대경로 링크는 백업)" 0
else
  report "fail-stale-relative-link (패키지 이동으로 끊어진 상대경로 링크는 백업)" 1 "$(ls -la "$CASE2C/home" 2>&1)"
fi

# 2d. fail-stale-relative-dirlink: GNU Stow는 ~/.githooks처럼 대상 디렉토리가 없으면
#     통째로 심볼릭 링크한다(tree-folding). 파일 단위로만 순회하면 이 디렉토리 링크
#     자체를 만나지 못해 정리가 안 됐다(실측: git/.githooks -> stow/git/.githooks 재현).
CASE2D="$TMP/case2d"
mkdir -p "$CASE2D/dotfiles/pkg/.hooksdir" "$CASE2D/home"
echo "dotfiles 버전" >"$CASE2D/dotfiles/pkg/.hooksdir/pre-commit"
ln -s "../old-location/pkg/.hooksdir" "$CASE2D/home/.hooksdir"

bash "$BACKUP" "pkg" "$CASE2D/dotfiles" "$CASE2D/home"

DIR_BACKUPS=("$CASE2D/home"/.hooksdir.backup.*)
if [ ! -e "$CASE2D/home/.hooksdir" ] && [ -L "${DIR_BACKUPS[0]}" ]; then
  report "fail-stale-relative-dirlink (패키지 이동으로 끊어진 디렉토리 링크는 백업)" 0
else
  report "fail-stale-relative-dirlink (패키지 이동으로 끊어진 디렉토리 링크는 백업)" 1 "$(ls -la "$CASE2D/home" 2>&1)"
fi

# 2e. fail-live-foreign-parent-dirlink: ~/.config 같은 공유 부모 디렉토리가 사용자의
#     살아있는 외부 symlink라면 stow-backup이 통째로 백업/교체하면 안 된다. 이 링크 아래에는
#     dotfiles와 무관한 앱 설정이 함께 있을 수 있으므로, 자동 takeover 대신 링크를 그대로
#     보존하고 명확하게 실패해야 사용자가 직접 충돌 정책을 결정할 수 있다.
CASE2E="$TMP/case2e"
mkdir -p "$CASE2E/dotfiles/pkg/.config/mise" "$CASE2E/home" "$CASE2E/config-store"
echo "dotfiles 버전" >"$CASE2E/dotfiles/pkg/.config/mise/config.toml"
echo "사용자 외부 설정" >"$CASE2E/config-store/unrelated.conf"
ln -s "../config-store" "$CASE2E/home/.config"

status=0
out=$(bash "$BACKUP" "pkg" "$CASE2E/dotfiles" "$CASE2E/home" 2>&1) || status=$?

if [ "$status" -ne 0 ] &&
  [ -L "$CASE2E/home/.config" ] &&
  [ "$(readlink "$CASE2E/home/.config")" = "../config-store" ] &&
  [ -f "$CASE2E/config-store/unrelated.conf" ] &&
  grep -qF "외부 디렉토리 심볼릭 링크" <<<"$out"; then
  report "fail-live-foreign-parent-dirlink (공유 부모의 사용자 symlink 보존 + fail-closed)" 0
else
  report "fail-live-foreign-parent-dirlink (공유 부모의 사용자 symlink 보존 + fail-closed)" 1 "exit=$status out=$out $(ls -la "$CASE2E/home" 2>&1)"
fi

# 2f. find can print entries and then fail. Process-substitution would
# swallow that status, moving user files even though the inventory is partial.
# Test failures in both directory and file scans before *any* backup mutation.
for FAIL_STAGE in 1 2; do
  CASE_FIND="$TMP/find-failure-$FAIL_STAGE"
  mkdir -p "$CASE_FIND/dotfiles/pkg/.hooks" "$CASE_FIND/home" "$CASE_FIND/fake-bin"
  printf 'managed hook\n' >"$CASE_FIND/dotfiles/pkg/.hooks/pre-commit"
  printf 'managed config\n' >"$CASE_FIND/dotfiles/pkg/.conflict"
  printf 'user config\n' >"$CASE_FIND/home/.conflict"
  ln -s "../old-stow/.hooks" "$CASE_FIND/home/.hooks"

  # The injected find emits a valid NUL-delimited entry before exit 77.
  # A successful first call delegates to the real find for normal ordering.
  cat >"$CASE_FIND/fake-bin/find" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count=0
if [ -f "$STOW_FIND_COUNTER" ]; then
  read -r count <"$STOW_FIND_COUNTER"
fi
count=$((count + 1))
printf '%s\n' "$count" >"$STOW_FIND_COUNTER"
if [ "$count" -eq "$STOW_FIND_FAIL_STAGE" ]; then
  if [ "$count" -eq 1 ]; then
    printf '%s\0' "$STOW_FIND_PARTIAL_DIR"
  else
    printf '%s\0' "$STOW_FIND_PARTIAL_FILE"
  fi
  exit 77
fi
exec "$STOW_FIND_REAL" "$@"
EOF
  chmod +x "$CASE_FIND/fake-bin/find"

  status=0
  out=$(STOW_FIND_COUNTER="$CASE_FIND/counter" \
    STOW_FIND_FAIL_STAGE="$FAIL_STAGE" \
    STOW_FIND_PARTIAL_DIR="$CASE_FIND/dotfiles/pkg/.hooks" \
    STOW_FIND_PARTIAL_FILE="$CASE_FIND/dotfiles/pkg/.conflict" \
    STOW_FIND_REAL="$(command -v find)" \
    PATH="$CASE_FIND/fake-bin:$PATH" \
    bash "$BACKUP" "pkg" "$CASE_FIND/dotfiles" "$CASE_FIND/home" 2>&1) || status=$?

  moved=0
  for backup in "$CASE_FIND/home/.hooks".backup.* "$CASE_FIND/home/.conflict".backup.*; do
    if [ -e "$backup" ] || [ -L "$backup" ]; then
      moved=1
    fi
  done
  if [ "$status" -ne 0 ] && [ "$moved" -eq 0 ] &&
    [ -L "$CASE_FIND/home/.hooks" ] &&
    [ "$(readlink "$CASE_FIND/home/.hooks")" = "../old-stow/.hooks" ] &&
    grep -qx 'user config' "$CASE_FIND/home/.conflict" &&
    grep -qF "Stow 소스 탐색 실패" <<<"$out"; then
    report "failed-find-stage-$FAIL_STAGE (부분 목록 이후 find 실패 → 사전 차단, 데이터 보존)" 0
  else
    report "failed-find-stage-$FAIL_STAGE (부분 목록 이후 find 실패 → 사전 차단, 데이터 보존)" 1 "exit=$status moved=$moved out=$out"
  fi
done

# 3. fail-same-second-collision: 같은 초에 같은 경로를 두 번 백업해도 첫 백업을
#    덮어쓰면 안 된다. date를 고정해 초 단위 timestamp 충돌을 결정적으로 재현한다.
CASE3="$TMP/case3"
mkdir -p "$CASE3/dotfiles/pkg" "$CASE3/home" "$CASE3/fixed-date-bin"
echo "dotfiles 버전" >"$CASE3/dotfiles/pkg/.repeatrc"
cat >"$CASE3/fixed-date-bin/date" <<'EOF'
#!/usr/bin/env bash
printf '2026-10-07-120000\n'
EOF
chmod +x "$CASE3/fixed-date-bin/date"

printf 'first-version\n' >"$CASE3/home/.repeatrc"
PATH="$CASE3/fixed-date-bin:$PATH" bash "$BACKUP" "pkg" "$CASE3/dotfiles" "$CASE3/home"
printf 'second-version\n' >"$CASE3/home/.repeatrc"
PATH="$CASE3/fixed-date-bin:$PATH" bash "$BACKUP" "pkg" "$CASE3/dotfiles" "$CASE3/home"

REPEAT_BACKUPS=("$CASE3/home"/.repeatrc.backup.*)
if [ "${#REPEAT_BACKUPS[@]}" -eq 2 ] &&
  grep -qx 'first-version' "${REPEAT_BACKUPS[0]}" &&
  grep -qx 'second-version' "${REPEAT_BACKUPS[1]}"; then
  report "fail-same-second-collision (기존 백업 보존 + 새 백업 별도 생성)" 0
else
  report "fail-same-second-collision (기존 백업 보존 + 새 백업 별도 생성)" 1 "$(ls -la "$CASE3/home" 2>&1)"
fi

# 4. ok-no-conflict: HOME에 해당 경로가 아예 없으면 아무 것도 하지 않고 exit 0이어야 한다.
CASE4="$TMP/case4"
mkdir -p "$CASE4/dotfiles/pkg" "$CASE4/home"
echo "dotfiles 버전" >"$CASE4/dotfiles/pkg/.newrc"

status=0
bash "$BACKUP" "pkg" "$CASE4/dotfiles" "$CASE4/home" || status=$?
if [ "$status" -eq 0 ] && [ ! -e "$CASE4/home/.newrc" ]; then
  report "ok-no-conflict (대상 없으면 무동작 + exit 0)" 0
else
  report "ok-no-conflict (대상 없으면 무동작 + exit 0)" 1 "exit=$status $(ls -la "$CASE4/home" 2>&1)"
fi

# 5. A Stow file must never move a user-owned directory (or an external
# live directory symlink) to a .backup.* name. Detect *all* such leaf collisions
# before moving any regular file; later failure must not partially migrate HOME.
CASE5="$TMP/case5"
mkdir -p "$CASE5/dotfiles/pkg" "$CASE5/home/.leaf-dir"
printf 'managed first\n' >"$CASE5/dotfiles/pkg/.first"
printf 'managed leaf\n' >"$CASE5/dotfiles/pkg/.leaf-dir"
printf 'user first\n' >"$CASE5/home/.first"
printf 'user nested\n' >"$CASE5/home/.leaf-dir/important"
status=0
out=$(bash "$BACKUP" pkg "$CASE5/dotfiles" "$CASE5/home" 2>&1) || status=$?
DIR5_BACKUPS=("$CASE5/home"/.leaf-dir.backup.*)
FIRST5_BACKUPS=("$CASE5/home"/.first.backup.*)
if [ "$status" -ne 0 ] &&
  grep -qF '[Hard Block]' <<<"$out" &&
  [ -d "$CASE5/home/.leaf-dir" ] &&
  grep -qx 'user nested' "$CASE5/home/.leaf-dir/important" &&
  grep -qx 'user first' "$CASE5/home/.first" &&
  [ ! -e "${DIR5_BACKUPS[0]}" ] &&
  [ ! -L "${DIR5_BACKUPS[0]}" ] &&
  [ ! -e "${FIRST5_BACKUPS[0]}" ]; then
  report "fail-real-directory-leaf (디렉터리 충돌 시 사전 차단, 이전 사용자 파일도 이동 금지)" 0
else
  report "fail-real-directory-leaf (디렉터리 충돌 시 사전 차단, 이전 사용자 파일도 이동 금지)" 1 "exit=$status out=$out"
fi

# A symlink to an external, existing directory must remain at its original
# path too: backing up only the symlink still severs the user's configuration.
CASE5B="$TMP/case5b"
mkdir -p "$CASE5B/dotfiles/pkg" "$CASE5B/home" "$CASE5B/external"
printf 'managed\n' >"$CASE5B/dotfiles/pkg/.linked-leaf"
printf 'user private\n' >"$CASE5B/external/private"
ln -s "$CASE5B/external" "$CASE5B/home/.linked-leaf"
status=0
out=$(bash "$BACKUP" pkg "$CASE5B/dotfiles" "$CASE5B/home" 2>&1) || status=$?
DIR5B_BACKUPS=("$CASE5B/home"/.linked-leaf.backup.*)
if [ "$status" -ne 0 ] &&
  grep -qF '[Hard Block]' <<<"$out" &&
  [ -L "$CASE5B/home/.linked-leaf" ] &&
  [ "$(readlink "$CASE5B/home/.linked-leaf")" = "$CASE5B/external" ] &&
  grep -qx 'user private' "$CASE5B/external/private" &&
  [ ! -e "${DIR5B_BACKUPS[0]}" ] &&
  [ ! -L "${DIR5B_BACKUPS[0]}" ]; then
  report "fail-external-directory-leaf (외부 사용자 디렉터리 링크 보존)" 0
else
  report "fail-external-directory-leaf (외부 사용자 디렉터리 링크 보존)" 1 "exit=$status out=$out"
fi

# After the user manually resolves the directory collision, the next run
# must still back up ordinary conflicting files without losing their content.
mv "$CASE5/home/.leaf-dir" "$CASE5/manual-save"
status=0
bash "$BACKUP" pkg "$CASE5/dotfiles" "$CASE5/home" || status=$?
RETRY5_BACKUPS=("$CASE5/home"/.first.backup.*)
if [ "$status" -eq 0 ] &&
  [ ! -e "$CASE5/home/.first" ] &&
  [ -f "${RETRY5_BACKUPS[0]}" ] &&
  grep -qx 'user first' "${RETRY5_BACKUPS[0]}" &&
  grep -qx 'user nested' "$CASE5/manual-save/important"; then
  report "ok-directory-collision-retry (사용자 수동 해결 후 일반 파일 안전 백업)" 0
else
  report "ok-directory-collision-retry (사용자 수동 해결 후 일반 파일 안전 백업)" 1 "exit=$status"
fi

# 6. A late live foreign directory symlink used to block *after* earlier
# stale directory links had already been moved. Validate the whole directory
# inventory before any mutation; determine find order from the fixture rather
# than assuming GNU/BSD filesystem traversal order.
CASE6="$TMP/case6"
mkdir -p "$CASE6/dotfiles/pkg/.alpha" "$CASE6/dotfiles/pkg/.omega" "$CASE6/home" "$CASE6/external"
printf 'managed alpha\n' >"$CASE6/dotfiles/pkg/.alpha/config"
printf 'managed omega\n' >"$CASE6/dotfiles/pkg/.omega/config"
printf 'user private\n' >"$CASE6/external/private"
CASE6_DIRS=()
while IFS= read -r -d '' dir; do
  CASE6_DIRS+=("${dir##*/}")
done < <(find "$CASE6/dotfiles/pkg" -mindepth 1 -type d -print0)
if [ "${#CASE6_DIRS[@]}" -ne 2 ]; then
  echo 'FAIL: invalid foreign-dir fixture'
  exit 1
fi
CASE6_FIRST=${CASE6_DIRS[0]}
CASE6_SECOND=${CASE6_DIRS[1]}
ln -s "../old-location/${CASE6_FIRST}" "$CASE6/home/$CASE6_FIRST"
ln -s "$CASE6/external" "$CASE6/home/$CASE6_SECOND"

status=0
out=$(bash "$BACKUP" pkg "$CASE6/dotfiles" "$CASE6/home" 2>&1) || status=$?
CASE6_BACKUPS=("$CASE6/home/$CASE6_FIRST".backup.*)
if [ "$status" -ne 0 ] &&
  grep -qF '외부 디렉토리 심볼릭 링크' <<<"$out" &&
  [ -L "$CASE6/home/$CASE6_FIRST" ] &&
  [ "$(readlink "$CASE6/home/$CASE6_FIRST")" = "../old-location/$CASE6_FIRST" ] &&
  [ -L "$CASE6/home/$CASE6_SECOND" ] &&
  [ "$(readlink "$CASE6/home/$CASE6_SECOND")" = "$CASE6/external" ] &&
  grep -qx 'user private' "$CASE6/external/private" &&
  [ ! -e "${CASE6_BACKUPS[0]}" ] &&
  [ ! -L "${CASE6_BACKUPS[0]}" ]; then
  report "fail-late-foreign-dirlink (사전 차단으로 다른 사용자 링크도 원위치 보존)" 0
else
  report "fail-late-foreign-dirlink (사전 차단으로 다른 사용자 링크도 원위치 보존)" 1 "exit=$status out=$out"
fi

# After the owner manually removes the conflicting foreign link from this
# disposable HOME, a retry should still back up the stale managed link and
# must not mutate the foreign directory or its contents.
rm "$CASE6/home/$CASE6_SECOND"
status=0
bash "$BACKUP" pkg "$CASE6/dotfiles" "$CASE6/home" || status=$?
CASE6_RETRY_BACKUPS=("$CASE6/home/$CASE6_FIRST".backup.*)
if [ "$status" -eq 0 ] &&
  [ ! -L "$CASE6/home/$CASE6_FIRST" ] &&
  [ -L "${CASE6_RETRY_BACKUPS[0]}" ] &&
  [ "$(readlink "${CASE6_RETRY_BACKUPS[0]}")" = "../old-location/$CASE6_FIRST" ] &&
  grep -qx 'user private' "$CASE6/external/private"; then
  report "ok-foreign-dirlink-retry (사용자 충돌 해결 후 정상 백업·외부 데이터 보존)" 0
else
  report "ok-foreign-dirlink-retry (사용자 충돌 해결 후 정상 백업·외부 데이터 보존)" 1 "exit=$status"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
