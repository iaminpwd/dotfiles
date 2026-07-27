#!/usr/bin/env bash
# handoff-check.sh - agent-handoff 프로토콜 상태 검증기
#
# 이 스크립트는 핸드오프 왕복의 "구조적 상태"만 판정한다. 리포트에 적힌 완료 주장이
# 사실인지는 파일 배치로 드러나지 않으므로 여기서 판정하지 않는다(그것은 아키텍트의
# 항목별 독립 재확인 몫이다). 규칙 위반이 파일 배치로 드러나는 항목만 기계 판정해,
# 지금까지 조항 문장에만 의존하던 안전장치를 사람/AI의 성실성과 분리한다.
#
# ERROR (exit 1): 통신 파일 동시 존재, task-id 누락, 3왕복 상한 초과
# WARNING (exit 0): task-id 승계 누락 의심, 아카이브 폴더명 형식 위반
#
# --commit-gate 모드에서는 3왕복 상한만 WARNING 으로 내린다. 상한의 목적은 "에이전트
# 루프를 멈추라"이지 "커밋하지 말라"가 아니다. 상한을 넘긴 상황에서는 오히려 지금까지의
# 작업을 커밋해 두고 사용자에게 개입을 요청하는 것이 정상 흐름이므로, 그 커밋을 막으면
# 안 된다. 에이전트가 직접 호출할 때는 ERROR 그대로 두어 루프를 멈추게 한다.
#
# 사용:
#   bash handoff-check.sh [대상_루트]
#   bash handoff-check.sh --commit-gate [대상_루트]
#   bash handoff-check.sh --run-verification <설계도.md> [대상_루트]

set -euo pipefail

BLUEPRINT="Claude-to-Gemini.md"
REPORT="Gemini-to-Claude.md"
ARCHIVE=".ai-handoff-archive"
TASK_ID_RE='^task-id: [0-9]{8}_[0-9]{6}$'
DIR_RE='^[0-9]{8}_[0-9]{6}$'
EXIT_CODE=0

# 설계도의 '## 4. Verification' 섹션에서 첫 bash 코드펜스 본문만 뽑아낸다.
extract_verification() {
  awk '
    /^## 4\. Verification/ { insec = 1; next }
    insec && /^## /        { exit }
    insec && /^```/        { if (infence) exit; infence = 1; next }
    insec && infence       { print }
  ' "$1"
}

# --run-verification: 설계도가 스스로 선언한 검증 명령을 아키텍트의 판단과 무관하게
# 그대로 재실행한다. 설계도의 쉘 코드를 실행하므로 자동 훅에 연결하지 말고 사람이
# 명시적으로 호출한다.
if [ "${1:-}" = "--run-verification" ]; then
  BLUEPRINT_FILE="${2:?사용: handoff-check.sh --run-verification <설계도.md> [대상_루트]}"
  ROOT="${3:-$(dirname "$BLUEPRINT_FILE")}"
  [ -f "$BLUEPRINT_FILE" ] || {
    echo "❌ [ERROR] 설계도를 찾을 수 없습니다: $BLUEPRINT_FILE" >&2
    exit 1
  }
  BLOCK=$(extract_verification "$BLUEPRINT_FILE")
  [ -n "$BLOCK" ] || {
    echo "❌ [ERROR] '## 4. Verification' 에서 bash 코드펜스를 찾지 못했습니다: $BLUEPRINT_FILE" >&2
    exit 1
  }
  echo "=== 설계도 검증 블록 재실행: $BLUEPRINT_FILE ==="
  echo "$BLOCK"
  echo "--- 실행 결과 ---"
  (cd "$ROOT" && bash -c "$BLOCK")
  echo "✅ 설계도 검증 블록이 종료 코드 0 으로 통과했습니다."
  exit 0
fi

COMMIT_GATE=0
if [ "${1:-}" = "--commit-gate" ]; then
  COMMIT_GATE=1
  shift
fi

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT" || {
  echo "❌ [ERROR] 대상 루트로 이동할 수 없습니다: $ROOT" >&2
  exit 1
}

# 핸드오프 산출물이 하나도 없으면 이 저장소는 프로토콜과 무관하다. 전역 pre-commit
# 훅에서 호출되므로 무관한 저장소에서는 아무 출력 없이 통과해야 한다.
if [ ! -e "$BLUEPRINT" ] && [ ! -e "$REPORT" ] && [ ! -d "$ARCHIVE" ]; then
  exit 0
fi

echo "--- Step: Agent Handoff State Check ($ROOT) ---"

# 1. 통신 파일 동시 존재: 아키텍트가 리포트를 소비(아카이브 이동)하지 않은 채 새 설계도를
#    발행했거나, 실행자가 선점 아카이브에 실패한 상태다. 트리거가 해제되지 않아 다음 턴에
#    양측이 서로를 다시 깨운다.
if [ -e "$BLUEPRINT" ] && [ -e "$REPORT" ]; then
  echo "❌ [ERROR] 통신 파일이 동시에 존재합니다 ($BLUEPRINT + $REPORT)." >&2
  echo "    소비한 파일을 $ARCHIVE/<task-id>/ 로 이동해 트리거를 해제하십시오." >&2
  EXIT_CODE=1
fi

# 2. task-id 누락: 아키텍트가 아카이브 경로를 확정할 수 없어 Consume & Clear 가 멈춘다.
for f in "$BLUEPRINT" "$REPORT"; do
  [ -f "$f" ] || continue
  if ! head -1 "$f" | grep -qE "$TASK_ID_RE"; then
    echo "❌ [ERROR] 첫 줄에 'task-id: <YYYYMMDD_HHMMSS>' 가 없습니다: $f" >&2
    EXIT_CODE=1
  fi
done

# 3. 3왕복 상한: 설계도+리포트 1쌍이 1왕복이므로 6개 초과는 상한 초과다.
# 4. 폴더명 형식 및 task-id 승계 누락 의심 (승계하면 한 폴더에 누적되므로, 폴더가
#    여러 개이면서 전부 1왕복에 머물러 있으면 왕복마다 새 발급했을 확률이 높다).
if [ -d "$ARCHIVE" ]; then
  single_round=0
  total_dirs=0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    total_dirs=$((total_dirs + 1))
    name=$(basename "$d")
    count=$(find "$d" -maxdepth 1 -type f | wc -l)
    if [ "$count" -gt 6 ]; then
      if [ "$COMMIT_GATE" -eq 1 ]; then
        echo "[WARNING] 3왕복 상한 초과: $ARCHIVE/$name 에 파일 ${count}개 (상한 6개)."
        echo "    커밋은 막지 않습니다. 양 에이전트는 작업을 중단하고 경과와 Blockers 를"
        echo "    사용자에게 브리핑하십시오."
      else
        echo "❌ [ERROR] 3왕복 상한 초과: $ARCHIVE/$name 에 파일 ${count}개 (상한 6개)." >&2
        echo "    양 에이전트는 작업을 중단하고 경과와 Blockers 를 사용자에게 브리핑하십시오." >&2
        EXIT_CODE=1
      fi
    fi
    [ "$count" -le 2 ] && single_round=$((single_round + 1))
    echo "$name" | grep -qE "$DIR_RE" ||
      echo "[WARNING] 아카이브 폴더명이 <YYYYMMDD_HHMMSS> 형식이 아닙니다: $ARCHIVE/$name"
  done < <(find "$ARCHIVE" -mindepth 1 -maxdepth 1 -type d | sort)

  if [ "$total_dirs" -ge 3 ] && [ "$single_round" -eq "$total_dirs" ]; then
    echo "[WARNING] 아카이브 폴더 ${total_dirs}개가 전부 1왕복(파일 2개 이하)에 머물러 있습니다."
    echo "    같은 작업의 재발행에 새 task-id 를 발급하면 3왕복 상한이 발동하지 않습니다."
  fi
fi

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "[INFO] 핸드오프 상태 검사 통과."
else
  echo "[INFO] 핸드오프 상태 검사 실패 — 위 ERROR 를 해소하십시오."
fi
exit "$EXIT_CODE"
