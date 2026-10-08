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

# A repository filename may contain literal shell substitutions. The diagnostic
# echo in the Justfile must never evaluate argument text as shell source.
INJECTION_NAME='$(touch${IFS}$JUST_INJECTION_MARKER).sh'
INJECTION_TARGET="$TMP/$INJECTION_NAME"
INJECTION_MARKER="$TMP/injected-by-just-echo"
printf '#!/usr/bin/env bash\n' >"$INJECTION_TARGET"
status=0
out=$(cd "$ROOT" && JUST_INJECTION_MARKER="$INJECTION_MARKER" just check-idempotency "$INJECTION_TARGET" 2>&1) || status=$?
if [ "$status" -ne 0 ] || [ -e "$INJECTION_MARKER" ]; then
  echo "FAIL: Justfile file argument executed shell commands or the check failed (exit=$status)." >&2
  printf '%s\n' "$out" >&2
  exit 1
fi
if ! grep -Fq "Idempotency check: '$INJECTION_TARGET'" <<<"$out"; then
  echo "FAIL: Filename with shell syntax was not passed to analyzer unchanged." >&2
  printf '%s\n' "$out" >&2
  exit 1
fi
echo 'PASS: Justfile filename substitutions stay literal'
