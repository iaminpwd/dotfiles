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
# 사용: safe-link-backup.sh <target>

set -euo pipefail

TARGET="$1"
BACKUP_TIMESTAMP=$(date +%F-%H%M%S)

if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
  mv "$TARGET" "$TARGET.backup.$BACKUP_TIMESTAMP"
  echo "  [BACKUP] $TARGET -> $TARGET.backup.$BACKUP_TIMESTAMP (실제 파일이 이미 있어 백업 후 링크 예정)"
fi
exit 0
