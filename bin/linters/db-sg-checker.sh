#!/usr/bin/env bash
# db-sg-checker.sh
# Terraform 코드를 정적 스캔하여 DB 인바운드 보안 그룹 소스가 Web/WAS로 한정되어 있는지 확인

set -euo pipefail

# 인자가 없으면 현재 디렉토리 스캔
TARGET_DIR="${1:-.}"

# .tf 파일이 없으면 조용히 종료 (하위 디렉토리 포함)
if ! find "$TARGET_DIR" -type f -name "*.tf" -print -quit | grep -q .; then
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
MATCHES=$(find "$TARGET_DIR" -type f -name "*.tf" -print0 | xargs -0 awk '
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
