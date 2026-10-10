#!/usr/bin/env bash
# test-safe-link-backup.sh
#
# safe-link-backup.py는 ansible.builtin.file(state: link, force: true)로 심볼릭 링크를
# 강제 생성하기 전, 목적지에 이미 있는 실제 파일/디렉토리를 백업으로 치우는 안전장치다.
# "이미 심볼릭 링크면 건드리지 않는다"는 조건이 깨지면 force가 어차피 안전하게 처리할
# 링크까지 불필요하게 백업해버리고(멱등성 위반), 반대로 "실제 파일이면 백업한다"가
# 깨지면 사용자의 실제 데이터가 백업 없이 사라진다(실측: ai_agent 롤의 force:true
# 심볼릭 링크 태스크들에 이 가드가 없었을 때의 잠재 위험).
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-safe-link-backup.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
SCRIPT="$REPO_ROOT/bin/utils/safe-link-backup.py"

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

echo "=== safe-link-backup.py 목적지 충돌 백업 로직 회귀 테스트 ==="

# 1. ok-no-target: 목적지가 아예 없으면 아무 것도 하지 않고 exit 0.
TARGET1="$TMP/no-target"
status=0
python3 "$SCRIPT" --targets "$TARGET1" || status=$?
if [ "$status" -eq 0 ] && [ ! -e "$TARGET1" ]; then
  report "ok-no-target (대상 없으면 무동작 + exit 0)" 0
else
  report "ok-no-target (대상 없으면 무동작 + exit 0)" 1 "exit=$status"
fi

# 2. fail-real-file: 목적지에 실제 파일이 있으면 백업으로 치운다.
TARGET2="$TMP/real-file"
echo "사용자 실제 데이터" >"$TARGET2"
python3 "$SCRIPT" --targets "$TARGET2"
BACKUPS2=("$TARGET2".backup.*)
if [ ! -e "$TARGET2" ] && [ -f "${BACKUPS2[0]}" ] && grep -qF "사용자 실제 데이터" "${BACKUPS2[0]}"; then
  report "fail-real-file (실제 파일이면 백업으로 이동)" 0
else
  report "fail-real-file (실제 파일이면 백업으로 이동)" 1 "$(ls -la "$TMP" 2>&1)"
fi

# 3. fail-real-dir: 목적지에 실제 디렉토리가 있으면(내용물째) 백업으로 치운다.
TARGET3="$TMP/real-dir"
mkdir -p "$TARGET3"
echo "사용자 실제 데이터" >"$TARGET3/inner.txt"
python3 "$SCRIPT" --targets "$TARGET3"
BACKUPS3=("$TARGET3".backup.*)
if [ ! -e "$TARGET3" ] && [ -d "${BACKUPS3[0]}" ] && [ -f "${BACKUPS3[0]}/inner.txt" ]; then
  report "fail-real-dir (실제 디렉토리는 내용물째 백업)" 0
else
  report "fail-real-dir (실제 디렉토리는 내용물째 백업)" 1 "$(ls -la "$TMP" 2>&1)"
fi

# 4. ok-already-symlink: 목적지가 이미 심볼릭 링크(어디를 가리키든)면 건드리지 않는다 —
#    force:true가 어차피 안전하게 교체하므로 여기서 손댈 필요가 없다.
TARGET4="$TMP/already-link"
ln -s "/some/arbitrary/target" "$TARGET4"
python3 "$SCRIPT" --targets "$TARGET4"
if [ -L "$TARGET4" ] && [ "$(readlink "$TARGET4")" = "/some/arbitrary/target" ]; then
  report "ok-already-symlink (이미 심볼릭 링크면 그대로 유지)" 0
else
  report "ok-already-symlink (이미 심볼릭 링크면 그대로 유지)" 1 "$(ls -la "$TMP" 2>&1)"
fi

# 4a. 설치 예정 원본과 다른 사용자 링크는 force:true 이전에 반드시 백업한다.
SRC4A="$TMP/managed source"
printf 'managed\n' >"$SRC4A"
OWN4A="$TMP/owned-link"
FOREIGN4A="$TMP/foreign-link"
BROKEN4A="$TMP/broken-foreign-link"
ln -s "$SRC4A" "$OWN4A"
ln -s "$TMP/external-user-config" "$FOREIGN4A"
ln -s "$TMP/missing-user-config" "$BROKEN4A"
python3 "$SCRIPT" --link-pairs "$SRC4A" "$OWN4A" "$SRC4A" "$FOREIGN4A" "$SRC4A" "$BROKEN4A"
BACKUP_FOREIGN4A=("$FOREIGN4A".backup.*)
BACKUP_BROKEN4A=("$BROKEN4A".backup.*)
if [ -L "$OWN4A" ] && [ "$(readlink "$OWN4A")" = "$SRC4A" ] &&
  [ "${#BACKUP_FOREIGN4A[@]}" -eq 1 ] && [ -L "${BACKUP_FOREIGN4A[0]}" ] &&
  [ "$(readlink "${BACKUP_FOREIGN4A[0]}")" = "$TMP/external-user-config" ] &&
  [ "${#BACKUP_BROKEN4A[@]}" -eq 1 ] && [ -L "${BACKUP_BROKEN4A[0]}" ] &&
  [ "$(readlink "${BACKUP_BROKEN4A[0]}")" = "$TMP/missing-user-config" ]; then
  report "source-aware-links (관리 링크 재사용·외부 링크와 broken 링크 백업)" 0
else
  report "source-aware-links (관리 링크 재사용·외부 링크와 broken 링크 백업)" 1
fi

# 매개변수의 쌍이 깨져 있으면 어떤 파일도 변경하지 않고 실패해야 한다.
ODD4A="$TMP/odd-pairs"
printf 'do-not-touch\n' >"$ODD4A"
status=0
python3 "$SCRIPT" --link-pairs "$SRC4A" "$ODD4A" "$SRC4A" >"$TMP/odd-output" 2>&1 || status=$?
if [ "$status" -eq 2 ] && grep -qx 'do-not-touch' "$ODD4A"; then
  report "invalid-pairs-fail-closed (홀수 인자는 실행 전 차단)" 0
else
  report "invalid-pairs-fail-closed" 1 "exit=$status"
fi

# 여러 경로의 공백·개행을 보존하고 정상 링크와 없는 경로는 건너뛴다.
TARGET5="$TMP/batch file"
TARGET6="$TMP/"$'batch\ndir'
printf 'batch data\n' >"$TARGET5"
mkdir "$TARGET6"
printf 'inner\n' >"$TARGET6/inner.txt"
python3 "$SCRIPT" --targets "$TARGET1" "$TARGET4" "$TARGET5" "$TARGET6"
BACKUPS5=("$TARGET5".backup.*)
BACKUPS6=("$TARGET6".backup.*)
if [ ! -e "$TARGET5" ] && [ ! -e "$TARGET6" ] &&
  grep -qx 'batch data' "${BACKUPS5[0]}" &&
  grep -qx inner "${BACKUPS6[0]}/inner.txt" && [ -L "$TARGET4" ]; then
  report "batch (복수 경로 백업 및 링크 보존)" 0
else
  report "batch (복수 경로 백업 및 링크 보존)" 1
fi

# 같은 초에 같은 경로를 두 번 백업해도 첫 백업을 덮어쓰면 안 된다.
# timestamp가 초 단위이므로 date를 고정해 충돌을 결정적으로 재현한다.
TARGET7="$TMP/same-second"
mkdir "$TMP/fixed-date-bin"
cat >"$TMP/fixed-date-bin/date" <<'EOF'
#!/usr/bin/env bash
printf '2026-10-07-120000\n'
EOF
chmod +x "$TMP/fixed-date-bin/date"

printf 'first-version\n' >"$TARGET7"
PATH="$TMP/fixed-date-bin:$PATH" python3 "$SCRIPT" --targets "$TARGET7"
printf 'second-version\n' >"$TARGET7"
PATH="$TMP/fixed-date-bin:$PATH" python3 "$SCRIPT" --targets "$TARGET7"

BACKUPS7=("$TARGET7".backup.*)
if [ "${#BACKUPS7[@]}" -eq 2 ] &&
  grep -qx 'first-version' "${BACKUPS7[0]}" &&
  grep -qx 'second-version' "${BACKUPS7[1]}"; then
  report "same-second-collision (기존 백업 보존 + 새 백업 별도 생성)" 0
else
  report "same-second-collision (기존 백업 보존 + 새 백업 별도 생성)" 1 "$(ls -la "$TMP" 2>&1)"
fi

# A competing process may claim the backup name right before our atomic
# link/mkdir call. sitecustomize injects that exact filesystem interleaving
# inside the Python helper without touching any global files or user HOME.
mkdir -p "$TMP/inject"
cat >"$TMP/inject/sitecustomize.py" <<'PY'
import os

_link = os.link
_mkdir = os.mkdir
_rename = os.rename
_claimed = False

def _inject(name, parent_fd):
    global _claimed
    if _claimed or name != os.environ.get("RACE_CANDIDATE"):
        return
    _claimed = True
    if os.environ.get("RACE_KIND") == "directory":
        _mkdir(name, dir_fd=parent_fd)
        with open(os.path.join(os.environ["RACE_PARENT"], name, "competitor.txt"), "w") as out:
            out.write("new competing backup\n")
    else:
        fd = os.open(name, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600,
                     dir_fd=parent_fd)
        try:
            os.write(fd, b"new competing backup\n")
        finally:
            os.close(fd)

def link(src, dst, *args, **kwargs):
    _inject(dst, kwargs.get("dst_dir_fd"))
    return _link(src, dst, *args, **kwargs)

def mkdir(path, *args, **kwargs):
    _inject(path, kwargs.get("dir_fd"))
    return _mkdir(path, *args, **kwargs)

def rename(src, dst, *args, **kwargs):
    if os.environ.get("RACE_SOURCE_SWAP") == "1" and dst == "source":
        fd = kwargs["src_dir_fd"]
        os.unlink(src, dir_fd=fd)
        replacement = os.open(src, os.O_CREAT | os.O_EXCL | os.O_WRONLY,
                              0o600, dir_fd=fd)
        try:
            os.write(replacement, b"new user replacement\n")
        finally:
            os.close(replacement)
    return _rename(src, dst, *args, **kwargs)

os.link = link
os.mkdir = mkdir
os.rename = rename
os.supports_dir_fd.add(link)
os.supports_follow_symlinks.add(link)
PY
for kind in file symlink directory; do
  RACE_TARGET="$TMP/backup-race-$kind"
  if [ "$kind" = file ]; then
    printf 'original user file\n' >"$RACE_TARGET"
  elif [ "$kind" = symlink ]; then
    ln -s "$TMP/original-user-link" "$RACE_TARGET"
  else
    mkdir "$RACE_TARGET"
    printf 'original nested file\n' >"$RACE_TARGET/child"
  fi
  RACE_BACKUP="$RACE_TARGET.backup.2026-10-07-120000"
  RACE_ARGS=(--targets "$RACE_TARGET")
  if [ "$kind" = symlink ]; then
    RACE_ARGS=(--link-pairs "$SRC4A" "$RACE_TARGET")
  fi
  code=0
  out=$(RACE_KIND="$kind" RACE_CANDIDATE="$(basename "$RACE_BACKUP")" \
  RACE_PARENT="$TMP" PYTHONPATH="$TMP/inject" \
  PATH="$TMP/fixed-date-bin:$PATH" \
    python3 "$SCRIPT" "${RACE_ARGS[@]}" 2>&1) || code=$?
  preserved=0
  case "$kind" in
  file)
    grep -qx 'original user file' "$RACE_BACKUP.1" && preserved=1
    ;;
  symlink)
    [ -L "$RACE_BACKUP.1" ] && [ "$(readlink "$RACE_BACKUP.1")" = "$TMP/original-user-link" ] && preserved=1
    ;;
  directory)
    grep -qx 'original nested file' "$RACE_BACKUP.1/child" && preserved=1
    ;;
  esac
  competitor_preserved=0
  if [ "$kind" = directory ]; then
    grep -qx 'new competing backup' "$RACE_BACKUP/competitor.txt" && competitor_preserved=1
  else
    grep -qx 'new competing backup' "$RACE_BACKUP" && competitor_preserved=1
  fi
  if [ "$code" -eq 0 ] && [ "$preserved" -eq 1 ] &&
    [ "$competitor_preserved" -eq 1 ] &&
    [ ! -e "$RACE_TARGET" ] && [ ! -L "$RACE_TARGET" ]; then
    report "concurrent-$kind-backup-name (동시 백업 이름 충돌 시 양쪽 사용자 데이터 보존)" 0
  else
    report "concurrent-$kind-backup-name (동시 백업 이름 충돌 시 양쪽 사용자 데이터 보존)" 1 "exit=$code out=$out"
  fi
done

# A replacement arriving *after* a successful backup-name claim must not be
# unlinked as if it were the original. Preserve it in the private stage and
# fail loudly; the original inode remains at the claimed backup path.
SOURCE_SWAP="$TMP/source-swap"
printf 'original user source\n' >"$SOURCE_SWAP"
swap_rc=0
swap_out=$(RACE_SOURCE_SWAP=1 PYTHONPATH="$TMP/inject" \
  PATH="$TMP/fixed-date-bin:$PATH" \
  python3 "$SCRIPT" --targets "$SOURCE_SWAP" 2>&1) || swap_rc=$?
STAGES=("$TMP/.source-swap.safe-stage-"*)
if [ "$swap_rc" -ne 0 ] &&
  grep -qx 'original user source' "$SOURCE_SWAP.backup.2026-10-07-120000" &&
  [ "${#STAGES[@]}" -eq 1 ] &&
  grep -qx 'new user replacement' "${STAGES[0]}/source" &&
  grep -qF 'private stage' <<<"$swap_out"; then
  report "concurrent-source-replacement (교체된 사용자 파일을 삭제하지 않고 별도 보존)" 0
else
  report "concurrent-source-replacement (교체된 사용자 파일을 삭제하지 않고 별도 보존)" 1 "exit=$swap_rc out=$swap_out"
fi

# 백업할 것이 없으면 date도 실행하지 않는다. 빈 대상 목록 역시 정상 무동작이다.
mkdir "$TMP/tools"
printf '#!/usr/bin/env bash\nexit 99\n' >"$TMP/tools/date"
chmod +x "$TMP/tools/date"
if PATH="$TMP/tools:$PATH" python3 "$SCRIPT" --targets "$TARGET1" "$TARGET4" "$TARGET5" "$TARGET6" &&
  PATH="$TMP/tools:$PATH" python3 "$SCRIPT" --targets; then
  report "no-op (재실행·빈 목록에서 date 호출 없음)" 0
else
  report "no-op (재실행·빈 목록에서 date 호출 없음)" 1
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
