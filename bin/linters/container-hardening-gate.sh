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
      # trivy 를 파이프 왼쪽에 두고 통째로 if 조건에 넣으면, trivy 자체가 실패했을 때
      # jq 가 빈 입력을 받아 1을 반환하고 "위반 없음"과 구분되지 않는다. 그 자리가 if
      # 조건문이라 set -e 도 개입하지 못해 DS-0002 하드 블록이 조용히 통과된다 —
      # 위 jq 부재 케이스와 정확히 같은 구멍이 스캐너 쪽에만 남아 있었다.
      # 결과를 먼저 파일로 받아 trivy 의 종료 코드를 독립적으로 판정한다.
      TRIVY_CONF_OUT=$(mktemp)
      TRIVY_CONF_RC=0
      trivy conf --format json "$TARGET" >"$TRIVY_CONF_OUT" 2>/dev/null || TRIVY_CONF_RC=$?
      if [ "$TRIVY_CONF_RC" -ne 0 ]; then
        echo "[ERROR] $TARGET 에 대한 trivy conf 스캔이 실패해(exit=$TRIVY_CONF_RC) DS-0002 판정을 내릴 수 없습니다."
        echo "        검증하지 못한 채로 통과시키지 않습니다. trivy 설치·설정을 확인하십시오."
        rm -f "$TRIVY_CONF_OUT"
        exit 1
      fi
      # trivy conf --format json 결과에서 DS-0002를 검색
      if "$JQ" -e '.Results[].Misconfigurations[]? | select(.ID == "DS-0002")' <"$TRIVY_CONF_OUT" >/dev/null 2>&1; then
        echo "[ERROR] $TARGET 내에 USER 권한이 누락되었습니다 (DS-0002 위반)."
        rm -f "$TRIVY_CONF_OUT"
        exit 1
      fi
      rm -f "$TRIVY_CONF_OUT"
    else
      echo "[WARNING] jq 도구가 없어 DS-0002 스캔을 건너뜁니다."
    fi
  else
    echo "[WARNING] trivy 도구가 없어 DS-0002 스캔을 건너뜁니다."
  fi
else
  # 빌드된 이미지 검증: dive 및 공급망 스캔
  #
  # 두 스캔 모두 출력을 임시 파일에 받아 두었다가 "실패했을 때만" 그대로 토해낸다.
  # 예전엔 >/dev/null 2>&1 로 전량 억제해서, 차단됐을 때 어떤 레이어가 낭비인지 / 어떤
  # CVE가 걸렸는지 알 방법이 전혀 없었다(게이트가 무엇을 고쳐야 하는지 못 알려주면
  # 사용자는 우회밖에 못 한다). 통과 시 무음은 compact-runner 표준대로 유지한다.
  if has_tool dive; then
    DIVE_OUT=$(mktemp)
    if ! dive "$TARGET" --ci --highestWastedBytes=20MB >"$DIVE_OUT" 2>&1; then
      echo "[ERROR] $TARGET 이미지 레이어 낭비율이 기준을 초과했습니다 (dive 검증 실패)."
      cat "$DIVE_OUT"
      rm -f "$DIVE_OUT"
      exit 1
    fi
    rm -f "$DIVE_OUT"
  else
    echo "[WARNING] dive 도구가 없어 레이어 낭비 스캔을 건너뜁니다."
  fi

  if has_tool trivy; then
    TRIVY_OUT=$(mktemp)
    if ! trivy image --exit-code 1 --severity CRITICAL,HIGH "$TARGET" >"$TRIVY_OUT" 2>&1; then
      echo "[ERROR] $TARGET 이미지 취약점 스캔에 실패했습니다."
      cat "$TRIVY_OUT"
      rm -f "$TRIVY_OUT"
      exit 1
    fi
    rm -f "$TRIVY_OUT"
  fi
fi

# 성공 시 출력 억제 (compact-runner 표준)
exit 0
