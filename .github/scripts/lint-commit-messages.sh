#!/usr/bin/env bash
# lint-commit-messages.sh
# push/PR로 실제 반영되는 커밋들을 stow/git/.githooks/commit-msg 훅으로 재검증한다.
# 로컬 훅은 --no-verify로 우회 가능하므로, ci.yml의 verify job이 이 재검증으로 최종 게이트 역할을 한다.
#
# 필요 환경변수: EVENT_NAME, BASE_SHA/HEAD_SHA(pull_request), BEFORE_SHA/AFTER_SHA(push)

set -euo pipefail

case "$EVENT_NAME" in
pull_request)
  COMMITS=$(git rev-list "$BASE_SHA..$HEAD_SHA")
  ;;
push)
  if [ "$BEFORE_SHA" = "0000000000000000000000000000000000000000" ]; then
    COMMITS="$AFTER_SHA"
  else
    COMMITS=$(git rev-list "$BEFORE_SHA..$AFTER_SHA")
  fi
  ;;
*)
  echo "이 이벤트($EVENT_NAME)는 커밋 범위를 판별할 수 없어 건너뜁니다."
  exit 0
  ;;
esac

FAILED=0
for sha in $COMMITS; do
  SOURCE=""
  [ -n "$(git rev-list --merges -n1 "$sha")" ] && SOURCE="merge"
  MSG_FILE=$(mktemp)
  git log --format=%B -n1 "$sha" >"$MSG_FILE"
  if ! bash stow/git/.githooks/commit-msg "$MSG_FILE" "$SOURCE"; then
    echo "  -> 위반 커밋: $sha ($(git log --format=%s -n1 "$sha"))"
    FAILED=1
  fi
  rm -f "$MSG_FILE"
done

[ "$FAILED" -eq 0 ]
