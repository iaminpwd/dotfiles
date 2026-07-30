#!/usr/bin/env bash
# container-hardening-gate.sh
# 컨테이너 이미지와 Dockerfile의 보안/하드닝 상태 자동 판정

set -euo pipefail

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  echo "[ERROR] 사용법: $0 <Dockerfile 경로 또는 이미지 이름>"
  exit 1
fi

if [ -f "$TARGET" ]; then
  # Dockerfile 검증: DS-0002(USER 권한 누락) 탐지
  if command -v trivy >/dev/null 2>&1; then
    # trivy conf --format json 결과에서 DS-0002를 검색
    if trivy conf --format json "$TARGET" 2>/dev/null | jq -e '.Results[].Misconfigurations[]? | select(.ID == "DS-0002")' >/dev/null 2>&1; then
      echo "[ERROR] $TARGET 내에 USER 권한이 누락되었습니다 (DS-0002 위반)."
      exit 1
    fi
  else
    echo "[WARNING] trivy 도구가 없어 DS-0002 스캔을 건너뜁니다."
  fi
else
  # 빌드된 이미지 검증: dive 및 공급망 스캔
  if command -v dive >/dev/null 2>&1; then
    if ! dive "$TARGET" --ci --highestWastedBytes=20MB >/dev/null 2>&1; then
      echo "[ERROR] $TARGET 이미지 레이어 낭비율이 기준을 초과했습니다 (dive 검증 실패)."
      exit 1
    fi
  else
    echo "[WARNING] dive 도구가 없어 레이어 낭비 스캔을 건너뜁니다."
  fi

  if command -v trivy >/dev/null 2>&1; then
    if ! trivy image --exit-code 1 --severity CRITICAL,HIGH "$TARGET" >/dev/null 2>&1; then
      echo "[ERROR] $TARGET 이미지 취약점 스캔에 실패했습니다."
      exit 1
    fi
  fi
fi

# 성공 시 출력 억제 (compact-runner 표준)
exit 0
