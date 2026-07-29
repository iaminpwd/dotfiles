#!/usr/bin/env bash
# db-sg-checker.sh
# Terraform 코드를 정적 스캔하여 DB 인바운드 보안 그룹 소스가 Web/WAS로 한정되어 있는지 확인

set -euo pipefail

# 인자가 없으면 현재 디렉토리 스캔
TARGET_DIR="${1:-.}"

# .tf 파일이 없으면 조용히 종료
if ! find "$TARGET_DIR" -maxdepth 1 -name "*.tf" -print -quit | grep -q .; then
  exit 0
fi

FAILED=0

# 아주 단순화된 정적 분석 로직 (MVP)
# 3306이나 5432를 여는 블록 내에 cidr_blocks = ["0.0.0.0/0"] 이 있는지 검사
if awk 'BEGIN{RS=""; FS="\n"} /(3306|5432)/ && /0\.0\.0\.0/' "$TARGET_DIR"/*.tf 2>/dev/null | grep -q .; then
  echo "[ERROR] DB 포트(3306/5432)가 0.0.0.0/0으로 열려있습니다. Web/WAS SG로 한정하십시오."
  FAILED=1
fi

# 이 스크립트에서는 개념 증명을 위해 특정 패턴을 중단하는 방식으로 구현했습니다.
# 추가로 보안 그룹 소스(source_security_group_id)가 *-was-sg 형식인지 확인하는 로직을 확장할 수 있습니다.

if [ "$FAILED" -eq 1 ]; then
  exit 1
fi

exit 0
