#!/usr/bin/env bash
# assert-idempotent-ansible-recap.sh
# bootstrap 2차 실행의 Ansible PLAY RECAP이 실제 changed=0에 수렴했는지 강제한다.
set -euo pipefail

LOG=${1:-}
if [ -z "$LOG" ] || [ ! -f "$LOG" ]; then
  echo "❌ [Idempotency] bootstrap 로그 파일을 찾을 수 없습니다: ${LOG:-<없음>}" >&2
  exit 1
fi

found=0
in_recap=0
while IFS= read -r line; do
  case "$line" in
  "PLAY RECAP "*)
    # 단순 카운터 로그가 아니라 실제 Ansible PLAY RECAP 이후의 행만 검사한다.
    in_recap=1
    ;;
  *" ok="*" changed="*" failed="*)
    [ "$in_recap" -eq 1 ] || continue
    changed=${line#* changed=}
    changed=${changed%%[!0-9]*}
    if [ -z "$changed" ] || [[ "$changed" == *[!0-9]* ]]; then
      echo "❌ [Idempotency] Ansible recap의 changed 값을 해석할 수 없습니다: $line" >&2
      exit 1
    fi
    found=1
    if [ "$changed" -ne 0 ]; then
      echo "❌ [Idempotency] 2차 bootstrap이 변경을 발생시켰습니다: changed=$changed" >&2
      echo "   $line" >&2
      exit 1
    fi
    ;;
  esac
done <"$LOG"

if [ "$found" -eq 0 ]; then
  echo "❌ [Idempotency] Ansible PLAY RECAP을 찾지 못했습니다. changed=0을 검증할 수 없습니다." >&2
  exit 1
fi

echo "✅ [Idempotency] 2차 bootstrap Ansible recap: changed=0"
