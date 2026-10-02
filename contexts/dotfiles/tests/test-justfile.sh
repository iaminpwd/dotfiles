#!/usr/bin/env bash
# Justfile의 explicit 파일 인자가 셸에서 분해되지 않고 검사기에 그대로 전달되는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

TARGET="$TMP/idempotency target.sh"
cat >"$TARGET" <<'EOF'
#!/usr/bin/env bash
echo value >> /tmp/idempotency-output
EOF
chmod +x "$TARGET"

status=0
out=$(cd "$ROOT" && just check-idempotency "$TARGET" 2>&1) || status=$?

if [ "$status" -ne 0 ]; then
  echo "FAIL: just check-idempotency가 공백 경로에서 실패했습니다: $out" >&2
  exit 1
fi

if ! grep -Fq "Idempotency check: '$TARGET'" <<<"$out"; then
  echo "FAIL: 공백이 포함된 explicit target이 실제 idempotency 검사기에 전달되지 않았습니다." >&2
  echo "$out" >&2
  exit 1
fi

echo 'PASS: Justfile check-idempotency가 공백 포함 파일 경로를 단일 인자로 전달'
