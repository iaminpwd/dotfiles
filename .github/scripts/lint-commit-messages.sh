#!/usr/bin/env bash
# lint-commit-messages.sh
# push/PR로 실제 반영되는 커밋들을 stow/git/.githooks/commit-msg 훅으로 재검증한다.
# 로컬 훅은 --no-verify로 우회 가능하므로, ci.yml의 verify job이 이 재검증으로 최종 게이트 역할을 한다.
#
# 필요 환경변수: EVENT_NAME, BASE_SHA/HEAD_SHA(pull_request), BEFORE_SHA/AFTER_SHA(push),
#                PUSHED_SHAS(push, force-push 폴백용 — 푸시 이벤트가 준 커밋 id 목록)

set -euo pipefail

case "$EVENT_NAME" in
pull_request)
  COMMITS=$(git rev-list "$BASE_SHA..$HEAD_SHA")
  ;;
push)
  if [ "$BEFORE_SHA" = "0000000000000000000000000000000000000000" ]; then
    COMMITS="$AFTER_SHA"
  elif git cat-file -e "${BEFORE_SHA}^{commit}" 2>/dev/null; then
    COMMITS=$(git rev-list "$BEFORE_SHA..$AFTER_SHA")
  else
    # force-push 로 히스토리를 재작성하면 이전 팁(github.event.before)이 어느 ref 에서도
    # 도달할 수 없게 되어 fetch 되지 않고, `git rev-list <없는 SHA>..` 가
    # "Invalid revision range" 로 죽는다(실측: 커밋 재구성 후 push 시 exit 128).
    #
    # 이 경우 "무엇이 새로 들어왔는지"를 커밋 그래프만으로는 알 수 없다. 대신 푸시
    # 이벤트 페이로드가 이번에 밀어 넣은 커밋 목록을 그대로 주므로 그것을 쓴다.
    # (전체 히스토리를 검사하는 폴백은 쓸 수 없다 — 이 저장소에는 컨벤션 도입 이전의
    #  레거시 커밋이 439개 중 81개 있어 CI 가 영구히 실패한다.)
    echo "ℹ️ 이전 팁($BEFORE_SHA)이 저장소에 없습니다(force-push로 히스토리가 재작성됨)."
    if [ -n "${PUSHED_SHAS:-}" ]; then
      echo "   푸시 이벤트가 보고한 커밋 목록으로 검증합니다."
      COMMITS="$PUSHED_SHAS"
    else
      # 페이로드의 commits 배열은 21개 이상 푸시 시 잘릴 수 있다. 그때는 최소한
      # 팁 커밋만이라도 검증하고, 축소 검증임을 눈에 띄게 남긴다(조용한 통과 방지).
      echo "⚠️ 푸시 이벤트 커밋 목록이 비어 있어 팁 커밋만 검증합니다(축소 검증)."
      COMMITS="$AFTER_SHA"
    fi
  fi
  ;;
*)
  echo "이 이벤트($EVENT_NAME)는 커밋 범위를 판별할 수 없어 건너뜁니다."
  exit 0
  ;;
esac

FAILED=0
for sha in $COMMITS; do
  # commit-msg 훅은 $2(COMMIT_SOURCE)가 "merge"면 검증을 건너뛴다. 그러므로 여기서는
  # "이 커밋 자신이 머지인가"만 물어야 한다.
  #
  # 예전엔 `git rev-list --merges -n1 "$sha"` 를 썼는데, 이건 "$sha 에서 도달 가능한
  # 머지 커밋"을 찾는 질의라 조상에 머지가 하나라도 있으면 항상 비어있지 않다. 그래서
  # 머지 PR이 한 번 들어온 뒤로는 모든 후속 커밋이 SOURCE="merge" 로 판정돼 훅이
  # 즉시 exit 0 했고, 이 게이트가 통째로 무력화됐다(실측: e914651 머지 이후 24개 커밋이
  # 한 번도 검증되지 않음). --no-walk 는 조상을 따라가지 않고 주어진 커밋 자체만 본다.
  SOURCE=""
  [ -n "$(git rev-list --no-walk --merges "$sha")" ] && SOURCE="merge"
  MSG_FILE=$(mktemp)
  git log --format=%B -n1 "$sha" >"$MSG_FILE"
  if ! bash stow/git/.githooks/commit-msg "$MSG_FILE" "$SOURCE"; then
    echo "  -> 위반 커밋: $sha ($(git log --format=%s -n1 "$sha"))"
    FAILED=1
  fi
  rm -f "$MSG_FILE"
done

[ "$FAILED" -eq 0 ]
