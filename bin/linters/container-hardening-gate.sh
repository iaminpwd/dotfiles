#!/usr/bin/env bash
# container-hardening-gate.sh
# 컨테이너 이미지와 Dockerfile의 보안/하드닝 상태 자동 판정

set -euo pipefail

# lib/ 경로를 리터럴로 분리하여 shellcheck SC1091 오류 회피 (심볼릭 링크 호출 호환성 보장)
CHG_SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source-path=SCRIPTDIR
source "$CHG_SCRIPT_DIR/../lib/jq-resolve.sh"
# mise shim 환경에서도 trivy/dive 가용성을 정확히 판정하기 위해 SSOT has_tool()을 재사용한다
# (command -v 직접 호출은 tool-probe.sh가 해결하는 mise shim 미해석 케이스를 다시 놓친다).
# shellcheck source-path=SCRIPTDIR
source "$CHG_SCRIPT_DIR/../lib/tool-probe.sh"

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  echo "[ERROR] 사용법: $0 <Dockerfile 경로 또는 이미지 이름>"
  exit 1
fi

if [ -f "$TARGET" ]; then
  # Dockerfile 검증: DS-0002(USER 권한 누락) 탐지
  if has_tool trivy; then
    # PATH의 jq(mise shim)가 격리된 $HOME 등에서 조용히 해석되지 않는 경우를 대비해
    # jq-resolve.sh SSOT로 검증한다(agent-edits-hook.sh/merge-agent-hooks.sh와 동일 패턴).
    # 이 확인 없이 바로 jq를 호출하면, jq 부재 시 파이프라인이 127로 실패하지만 그 자리가
    # if 조건문 안이라 set -e가 개입하지 못해 DS-0002 하드 블록이 조용히 통과돼 버린다.
    JQ=$(resolve_jq)
    if [ -n "$JQ" ] && "$JQ" --version >/dev/null 2>&1; then
      # trivy conf --format json 결과에서 DS-0002를 검색
      if trivy conf --format json "$TARGET" 2>/dev/null | "$JQ" -e '.Results[].Misconfigurations[]? | select(.ID == "DS-0002")' >/dev/null 2>&1; then
        echo "[ERROR] $TARGET 내에 USER 권한이 누락되었습니다 (DS-0002 위반)."
        exit 1
      fi
    else
      echo "[WARNING] jq 도구가 없어 DS-0002 스캔을 건너뜁니다."
    fi
  else
    echo "[WARNING] trivy 도구가 없어 DS-0002 스캔을 건너뜁니다."
  fi
else
  # 빌드된 이미지 검증: dive 및 공급망 스캔
  if has_tool dive; then
    if ! dive "$TARGET" --ci --highestWastedBytes=20MB >/dev/null 2>&1; then
      echo "[ERROR] $TARGET 이미지 레이어 낭비율이 기준을 초과했습니다 (dive 검증 실패)."
      exit 1
    fi
  else
    echo "[WARNING] dive 도구가 없어 레이어 낭비 스캔을 건너뜁니다."
  fi

  if has_tool trivy; then
    if ! trivy image --exit-code 1 --severity CRITICAL,HIGH "$TARGET" >/dev/null 2>&1; then
      echo "[ERROR] $TARGET 이미지 취약점 스캔에 실패했습니다."
      exit 1
    fi
  fi
fi

# 성공 시 출력 억제 (compact-runner 표준)
exit 0
