#!/usr/bin/env bash
# ai_agent role이 더 이상 저장소 스크립트를 ~/.local/bin에 평탄화하지 않고,
# 과거 버전이 만든 dotfiles 소유 링크만 안전하게 회수하는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
LOCAL_BIN="$TMP/home/.local/bin"
mkdir -p "$REPO/bin" "$REPO/contexts/demo/scripts" "$LOCAL_BIN" "$TMP/foreign"

cat >"$REPO/bin/live-tool.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$REPO/contexts/demo/scripts/live-context.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$TMP/foreign/live.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$REPO/bin/live-tool.sh" "$REPO/contexts/demo/scripts/live-context.sh" "$TMP/foreign/live.sh"

# 과거 ai_agent role이 만든 절대경로 링크(살아 있는 링크와 이미 깨진 링크)를 모두 합성한다.
ln -s "$REPO/bin/live-tool.sh" "$LOCAL_BIN/live-tool.sh"
ln -s "$REPO/contexts/demo/scripts/live-context.sh" "$LOCAL_BIN/live-context.sh"
ln -s "$REPO/bin/missing-tool.sh" "$LOCAL_BIN/missing-tool.sh"

# ~/.local/bin은 공유 경로이므로 외부 소유 링크는 살아 있든 깨졌든 보존해야 한다.
ln -s "$TMP/foreign/live.sh" "$LOCAL_BIN/foreign-live.sh"
ln -s "$TMP/foreign/missing.sh" "$LOCAL_BIN/foreign-broken.sh"

bash "$ROOT/bin/utils/prune-orphan-agent-scripts.sh" "$REPO" "$LOCAL_BIN"

for name in live-tool.sh live-context.sh missing-tool.sh; do
  if [ -L "$LOCAL_BIN/$name" ]; then
    echo "FAIL: 과거 dotfiles 소유 ~/.local/bin 링크가 남았습니다: $name"
    exit 1
  fi
done

for name in foreign-live.sh foreign-broken.sh; do
  if [ ! -L "$LOCAL_BIN/$name" ]; then
    echo "FAIL: 외부 사용자 소유 ~/.local/bin 링크까지 삭제했습니다: $name"
    exit 1
  fi
done

ROLE="$ROOT/ansible/roles/ai_agent/tasks/main.yml"
if grep -Fq 'dest: "{{ ansible_env.HOME }}/.local/bin/{{ item.path | basename }}"' "$ROLE" ||
   grep -Fq 'register: ai_agent_scripts_find' "$ROLE"; then
  echo 'FAIL: ai_agent role이 여전히 저장소 스크립트를 ~/.local/bin에 전역 평탄화합니다.'
  exit 1
fi

echo 'PASS: ai_agent는 새 global script link를 만들지 않고 기존 dotfiles 소유 링크만 회수함'
