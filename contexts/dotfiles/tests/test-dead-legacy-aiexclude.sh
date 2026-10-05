#!/usr/bin/env bash
# dead/legacy 설정 파일이 실제 배포·런타임 consumer 없이 남아 있지 않은지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
LEGACY="$ROOT/contexts/.base.aiexclude"

# .base.aiexclude는 과거 setup.sh/.zshrc가 각 context의 .aiexclude로 복사하던 템플릿이었다.
# 현재 그 provisioning 경로가 사라졌다면 파일만 남겨 "AI가 secrets를 제외한다"는 잘못된
# 보안 기대를 만들지 않도록 제거해야 한다. 다시 도입하려면 실제 실행 경로에서 소비되어야 한다.
if [ -f "$LEGACY" ]; then
  consumers=$(
    git -C "$ROOT" grep -lF '.base.aiexclude' HEAD -- bootstrap.sh Justfile ansible bin stow .github 2>/dev/null || true
  )
  if [ -z "$consumers" ]; then
    echo 'FAIL: contexts/.base.aiexclude가 실제 배포·런타임 consumer 없이 남아 있는 dead security config입니다.'
    exit 1
  fi
fi

echo 'PASS: orphaned .base.aiexclude legacy config 없음'
