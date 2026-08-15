#!/usr/bin/env bash
# db-sg-checker.sh
# Terraform 코드를 정적 스캔하여 DB 인바운드 보안 그룹 소스가 Web/WAS로 한정되어 있는지 확인

set -euo pipefail

# 인자가 없으면 현재 디렉토리 스캔
TARGET_DIR="${1:-.}"

# 의도적 위반을 담은 회귀 테스트 픽스처는 스캔 대상에서 제외한다. 이 검사기는
# pre-flight-check.sh 의 validate_terraform 이 저장소 루트(".")를 통째로 넘겨 호출하므로,
# 제외가 없으면 자기 저장소의 픽스처가 그대로 위반으로 잡혀 무관한 커밋이 영구 차단된다
# (실측: contexts/pre-flight-check/tests/fixtures-db-sg 의 fail-* 3건이 신고됨).
# 같은 함수의 checkov(--skip-path 'tests/fixtures')와 validate_security 의
# trivy(--skip-dirs '**/tests/fixtures*')는 이미 같은 이유로 같은 범위를 제외하고 있는데
# 이 검사기만 빠져 있었다. 끝에 * 를 붙여 fixtures-db-sg / fixtures-conftest 같은 접미사형
# 디렉토리까지 함께 덮는다(세 검증기의 제외 범위를 일치시킨다).
#
# 단, 스캔 루트로 픽스처 자신을 지목해 호출한 경우(회귀 테스트 test-db-sg.sh 가 각
# fail-* 디렉토리를 인자로 넘기는 방식)에는 제외하지 않는다. 무조건 걸러내면 그 테스트의
# 위반 픽스처가 전부 미탐이 되어, 정작 이 검사기의 판정 로직이 깨져도 아무도 잡지 못한다.
# checkov/trivy 의 제외 옵션도 스캔 루트 자체를 지정하면 그 안을 그대로 검사하므로
# 의미론이 일치한다.
FIXTURE_EXCLUDE=(! -path "*/tests/fixtures*")
case "$TARGET_DIR" in
*/tests/fixtures* | tests/fixtures*) FIXTURE_EXCLUDE=() ;;
esac

# .tf 파일이 없으면 조용히 종료 (하위 디렉토리 포함)
#
# `find ... | grep -q .` 형태를 쓰지 않는다. grep 이 첫 매치에서 stdin 을 닫으면 find 가
# SIGPIPE(141)로 끝나고, set -o pipefail 이 그것을 파이프라인 결과로 채택해 ".tf 가 있는데
# 없다"로 뒤집힌다 — 그러면 DB SG 검사가 통째로 조용히 건너뛰어진다. 현재는 find 가 -quit 로
# 즉시 끝나 발현되지 않지만, 같은 함정을 이 저장소는 이미 aws/tests/run.sh / prompt-lint.sh
# 두 곳에서 고쳤다(파이프 버퍼 안에 들어가 안 터질 뿐 구조는 동일). 파이프 자체를 없앤다.
if [ -z "$(find "$TARGET_DIR" -type f -name "*.tf" "${FIXTURE_EXCLUDE[@]}" -print -quit)" ]; then
  exit 0
fi

FAILED=0

# DB 포트(3306/5432)를 여는 "인그레스 규칙 블록" 안에 0.0.0.0/0 이 있는지 검사한다.
#
# 예전에는 awk 문단 모드(RS="")로 "빈 줄로 나뉜 덩어리에 3306과 0.0.0.0이 같이 있으면
# 위반"으로 판정했다. 이건 두 방향으로 다 틀렸다:
#  - 오탐: 같은 리소스 안에서 ingress(3306, 특정 SG)와 egress(0.0.0.0/0, 정상)가 나란히
#    선언된 흔한 패턴이 통째로 한 문단이라 무조건 걸렸다. egress 전체 개방은 지극히
#    정상인데 커밋이 막힌다.
#  - 미탐: 반대로 블록 사이에 빈 줄이 없으면 파일 전체가 한 문단이 되어, 무관한 위치의
#    3306과 0.0.0.0이 우연히 같이 있어도 걸리고, 정작 블록 단위 판정은 사라진다.
#
# 대신 중괄호 깊이를 세어 ingress(또는 type = "ingress") 블록의 범위를 실제로 추적하고,
# 그 블록 안에서만 DB 포트와 0.0.0.0/0 의 공존을 판정한다. egress 블록은 대상에서 뺀다.
# $0/$1 은 awk 자신의 필드 변수이므로 셸이 전개하면 안 된다. 홑따옴표가 맞다.
# shellcheck disable=SC2016
MATCHES=$(find "$TARGET_DIR" -type f -name "*.tf" "${FIXTURE_EXCLUDE[@]}" -print0 | xargs -0 awk '
  # 파일이 바뀌면 블록 추적 상태를 초기화한다(여러 파일을 한 awk 프로세스로 받기 때문).
  FNR == 1 { in_block = 0; depth = 0 }

  {
    line = $0
    sub(/#.*/, "", line)   # 주석 안의 0.0.0.0/0 등을 코드로 오인하지 않도록 제거

    if (!in_block) {
      # 인그레스 블록 진입 판정. egress 는 의도적으로 대상에서 제외한다.
      #   - `ingress {`                              : 인라인 블록
      #   - `dynamic "ingress" {`                    : for_each 로 규칙을 생성하는 흔한 패턴.
      #     블록 이름이 따옴표 안에 있어 위 `ingress {` 패턴에 걸리지 않으므로 따로 받는다
      #     (누락 시 dynamic 으로 연 0.0.0.0/0 개방이 통째로 미탐된다).
      #   - aws_vpc_security_group_ingress_rule      : 방향이 리소스 타입에 고정된 신형 리소스
      #   - aws_security_group_rule                  : 방향이 type 인자로 갈리는 구형 리소스
      if (line ~ /(^|[^_a-zA-Z])ingress[[:space:]]*\{/ ||
          line ~ /dynamic[[:space:]]+"?ingress"?[[:space:]]*\{/ ||
          line ~ /resource[[:space:]]+"aws_vpc_security_group_ingress_rule"/ ||
          line ~ /resource[[:space:]]+"aws_security_group_rule"/) {
        in_block = 1; depth = 0; has_port = 0; has_open = 0; is_egress = 0
        block_start = FILENAME ":" FNR
      } else {
        next
      }
    }

    # 블록 내부 판정
    if (line ~ /(3306|5432)/) has_port = 1
    if (line ~ /0\.0\.0\.0\/0/) has_open = 1
    # aws_security_group_rule 은 type 인자로 방향이 갈리므로 egress 면 대상에서 뺀다.
    if (line ~ /type[[:space:]]*=[[:space:]]*"egress"/) is_egress = 1

    # 중괄호 깊이 추적
    n_open = gsub(/\{/, "{", line)
    n_close = gsub(/\}/, "}", line)
    depth += n_open - n_close

    if (depth <= 0) {
      if (has_port && has_open && !is_egress) print block_start
      in_block = 0
    }
  }
' 2>/dev/null || true)
if [ -n "$MATCHES" ]; then
  echo "[ERROR] DB 포트(3306/5432)가 0.0.0.0/0으로 열려있습니다. Web/WAS SG로 한정하십시오."
  while IFS= read -r loc; do
    [ -n "$loc" ] && echo "         위반 위치: $loc"
  done <<<"$MATCHES"
  FAILED=1
fi

# 이 스크립트에서는 개념 증명을 위해 특정 패턴을 중단하는 방식으로 구현했습니다.
# 추가로 보안 그룹 소스(source_security_group_id)가 *-was-sg 형식인지 확인하는 로직을 확장할 수 있습니다.

if [ "$FAILED" -eq 1 ]; then
  exit 1
fi

exit 0
