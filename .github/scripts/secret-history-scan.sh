#!/usr/bin/env bash
# PR/push에서 최종 워킹트리에 남지 않은 중간 커밋의 시크릿까지 검사한다.
set -euo pipefail

if ! command -v trufflehog >/dev/null 2>&1 || ! trufflehog --version >/dev/null 2>&1; then
  echo "❌ [Hard Block] Git 히스토리 시크릿 스캔에 필요한 trufflehog를 실행할 수 없습니다." >&2
  exit 1
fi

event=${EVENT_NAME:-}
head=""
base_candidate=""

case "$event" in
pull_request)
  base_candidate=${BASE_SHA:-}
  head=${HEAD_SHA:-${CURRENT_SHA:-}}
  ;;
push)
  base_candidate=${BEFORE_SHA:-}
  head=${AFTER_SHA:-${CURRENT_SHA:-}}
  ;;
*)
  # workflow_dispatch 등 범위 정보가 없는 실행은 현재 커밋 1개를 검사한다.
  head=${CURRENT_SHA:-HEAD}
  if git rev-parse --verify -q "${head}^" >/dev/null; then
    base_candidate="${head}^"
  fi
  ;;
esac

[ -n "$head" ] || head=HEAD
if ! git cat-file -e "${head}^{commit}" 2>/dev/null; then
  echo "❌ [Hard Block] 시크릿 스캔 head 커밋을 찾을 수 없습니다: $head" >&2
  exit 1
fi

base=""
if [ -n "$base_candidate" ] &&
  [ "$base_candidate" != "0000000000000000000000000000000000000000" ]; then
  if ! git cat-file -e "${base_candidate}^{commit}" 2>/dev/null; then
    echo "❌ [Hard Block] 시크릿 스캔 base 커밋을 찾을 수 없습니다: $base_candidate" >&2
    exit 1
  fi
  if ! base=$(git merge-base "$base_candidate" "$head"); then
    echo "❌ [Hard Block] 시크릿 스캔 범위의 merge-base를 계산할 수 없습니다." >&2
    exit 1
  fi
elif git rev-parse --verify -q "${head}^" >/dev/null; then
  base="${head}^"
fi

output=$(mktemp)
trap 'rm -f "$output"' EXIT

args=(git file://. --branch "$head" --no-update --fail)
if [ -n "$base" ]; then
  args+=(--since-commit "$base")
fi

rc=0
trufflehog "${args[@]}" >"$output" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
  # 탐지 결과 원문에는 실제 자격 증명 조각이 포함될 수 있으므로 CI 로그에 재출력하지 않는다.
  echo "❌ [Hard Block] Git 커밋 범위에서 시크릿 또는 스캔 오류가 감지되었습니다." >&2
  echo "   범위: ${base:-<root>}..$head / trufflehog exit=$rc" >&2
  echo "   상세 결과는 로컬에서 동일 명령을 실행해 확인하고, 노출된 자격 증명은 즉시 폐기하십시오." >&2
  exit 1
fi

echo "  -> [✓] trufflehog Git history secret scan passed (${base:-<root>}..$head)"
