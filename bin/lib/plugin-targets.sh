#!/usr/bin/env bash
# plugin-targets.sh - bin/hooks/plugins/*.sh 위임 검증기의 검사 대상 수집 공용 라이브러리 (SSOT)
#
# [배경 — 실측 재현된 무검증 통과 버그]
# pre-flight-check.sh 는 대상 파일을 main() 에서 한 번만 수집하고(staged/changed/all/
# explicit 4가지 모드) 각 검증 함수가 filter_target_files 로 자기 확장자만 골라 쓰는
# "수집-필터링 분리" 구조다. 그런데 위임 플러그인 3개(k8s/observability/aiops)만 이
# 구조 밖에 있었다: run_delegated_skill_checks 가 인자 없이 `bash <plugin>` 으로 호출하고
# 플러그인은 저마다 `git diff --cached` 를 하드코딩해, 실행 모드와 무관하게 항상
# "스테이징된 것"만 봤다.
#
# 그 결과 문법이 깨진 PrometheusRule 하나로 실측했을 때:
#   staged 모드   -> exit 1 (잡음)
#   --all 모드    -> exit 0 (놓침)   <- just verify / CI 가 쓰는 모드
#   explicit 모드 -> exit 0 (놓침)   <- pre-flight-live-hook.sh 가 AI 편집마다 쓰는 모드
# 즉 --all/--changed/explicit 경로에서는 Kyverno·PromQL·deprecated API·텔레메트리 시크릿
# 검증이 통째로 비어 있으면서 초록불만 떴다.
#
# 이 라이브러리는 그 구멍을 메운다. 플러그인은 인자로 대상 목록을 받으면 그걸 쓰고,
# 인자 없이 직접 호출되면(각 스킬의 회귀 테스트, 수동 실행) 기존처럼 스테이징 기준으로
# 폴백한다 — 기존 호출 계약을 깨지 않으면서 모드 인지만 추가하는 방식이다.
#
# [주의] source 전용 라이브러리이므로 호출자의 셸 옵션을 보존하기 위해 set -euo pipefail을 선언하지 않습니다.
#
# 사용법:
#   source "$LIB_PATH/plugin-targets.sh"
#   PLUGIN_TARGET_FILES=("$@")        # 스크립트 최상단에서 argv 를 그대로 넘길 것
#   mapfile -d '' -t files < <(plugin_target_files '*.yaml' '*.yml')

# 호출부가 argv 를 넘기기 전에도 참조될 수 있으므로 빈 배열로 선언해 둔다(set -u 방어).
PLUGIN_TARGET_FILES=()

# plugin_target_files <glob 패턴...>
# stdout: NUL 구분 대상 파일 목록
#
# 패턴은 셸 글롭이자 git pathspec 으로 양쪽 경로에서 동일하게 해석된다
# (예: '*.yaml', '*kyverno-test.yaml').
plugin_target_files() {
  local pattern f

  if [ "${#PLUGIN_TARGET_FILES[@]}" -gt 0 ]; then
    for f in "${PLUGIN_TARGET_FILES[@]}"; do
      [ -n "$f" ] || continue
      for pattern in "$@"; do
        # 우변은 글롭 패턴이므로 의도적으로 인용하지 않는다(pre-flight-check.sh 의
        # filter_target_files 와 동일한 매칭 규칙).
        # shellcheck disable=SC2053
        if [[ "$f" == $pattern ]]; then
          printf '%s\0' "$f"
          break
        fi
      done
    done
    return 0
  fi

  # 인자 없이 직접 호출된 경우: 종전과 동일하게 스테이징 기준으로 폴백한다.
  # --no-renames 를 쓰는 이유는 pre-flight-check.sh 의 staged 수집부 주석 참조
  # (rename 이 --diff-filter=ACM 에서 통째로 빠져 대상 0건이 된다).
  [ "${GLOBAL_IS_GIT_REPO:-0}" -eq 1 ] || return 0
  git diff --cached --name-only -z --no-renames --diff-filter=ACM -- "$@" 2>/dev/null
}
