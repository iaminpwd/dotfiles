#!/usr/bin/env bash
# safe-link-backup.sh
# ansible.builtin.file(state: link, force: true)로 심볼릭 링크를 강제 생성하기 전,
# 그 목적지에 이미 있는 "실제(비-심볼릭) 파일/디렉토리"를 백업으로 치운다.
#
# force: true는 목적지가 이미 존재하면 그게 무엇이든 조용히 덮어쓴다. 목적지 이름이
# 우연히 이 저장소가 배포하는 이름과 겹치는 사용자 자신의 파일(예: ~/.local/bin/foo.sh를
# 직접 만들어 둔 경우)이 있으면 백업 없이 사라진다. 이미 우리가 만든 심볼릭 링크(같은
# 대상을 가리키든 아니든)는 어차피 force가 안전하게 교체하므로 건드리지 않는다 — 오직
# "실제 파일/디렉토리가 그 자리를 차지하고 있는" 경우만 백업 대상이다.
#
# 백업 이름은 초 단위 timestamp를 기본으로 쓰되 같은 초에 같은 경로를 다시 백업하면
# 기존 백업을 덮어쓰지 않도록 .1, .2 ... suffix로 다음 빈 이름을 찾는다.
#
# 사용: safe-link-backup.sh [target ...]

set -euo pipefail

_next_backup_path() {
  local target=$1 timestamp=$2 candidate suffix=0
  candidate="$target.backup.$timestamp"

  while [ -e "$candidate" ] || [ -L "$candidate" ]; do
    suffix=$((suffix + 1))
    candidate="$target.backup.$timestamp.$suffix"
  done

  printf '%s\n' "$candidate"
}

for TARGET in "$@"; do
  if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
    BACKUP_TIMESTAMP=$(date +%F-%H%M%S)
    BACKUP_PATH=$(_next_backup_path "$TARGET" "$BACKUP_TIMESTAMP")
    mv "$TARGET" "$BACKUP_PATH"
    echo "  [BACKUP] $TARGET -> $BACKUP_PATH (실제 파일이 이미 있어 백업 후 링크 예정)"
  fi
done
exit 0
