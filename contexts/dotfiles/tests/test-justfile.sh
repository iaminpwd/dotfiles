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
# shellcheck disable=SC2016 # a literal shell fragment in an adversarial filename
INJECTION_NAME='$(touch${IFS}$JUST_INJECTION_MARKER).sh'
INJECTION_TARGET="$TMP/$INJECTION_NAME"
INJECTION_MARKER="$TMP/injected-by-just-echo"
printf 'echo value >> /tmp/unused\n' >"$INJECTION_TARGET"
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

# docs-index must replace the index atomically in its own directory, while
# preserving the current document's access mode and leaving it intact on errors.
INDEX_FAKE="$TMP/docs-index-repo"
mkdir -p "$INDEX_FAKE/contexts" "$INDEX_FAKE/bin/utils" "$INDEX_FAKE/mock-bin"
cp "$ROOT/Justfile" "$INDEX_FAKE/Justfile"
cat >"$INDEX_FAKE/bin/utils/generate-context-index.sh" <<'GEN'
#!/usr/bin/env bash
printf '# regenerated index\n'
if [ "${INDEX_FIXTURE_FAIL:-0}" = 1 ]; then
  printf '# partial content\n'
  exit 19
fi
GEN
cat >"$INDEX_FAKE/mock-bin/mv" <<'MOVE'
#!/usr/bin/env bash
set -euo pipefail
source_file=$1
source_dir=$(cd -P "$(dirname "$source_file")" && pwd)
if [ "$source_dir" != "$INDEX_EXPECTED_DIR" ]; then
  echo "FAIL: docs-index temp is outside the destination filesystem: $source_file" >&2
  exit 88
fi
exec /bin/mv "$@"
MOVE
chmod +x "$INDEX_FAKE/mock-bin/mv"
INDEX_FILE="$INDEX_FAKE/contexts/INDEX.md"
printf '# existing index\n' >"$INDEX_FILE"
index_mode() {
  stat -c %a "$INDEX_FILE" 2>/dev/null || stat -f %Lp "$INDEX_FILE"
}
for expected_mode in 644 640; do
  chmod "$expected_mode" "$INDEX_FILE"
  index_rc=0
  index_out=$(cd "$INDEX_FAKE" && INDEX_EXPECTED_DIR="$INDEX_FAKE/contexts" PATH="$INDEX_FAKE/mock-bin:$PATH" just docs-index 2>&1) || index_rc=$?
  if [ "$index_rc" -ne 0 ] || ! grep -qx '# regenerated index' "$INDEX_FILE" ||
    [ "$(index_mode)" != "$expected_mode" ]; then
    echo "FAIL: docs-index replacement must use same-directory rename and preserve mode $expected_mode (exit=$index_rc, mode=$(index_mode))" >&2
    printf '%s\n' "$index_out" >&2
    exit 1
  fi
done
echo 'PASS: docs-index keeps original mode and uses same-directory rename'

# Generation that emits a partial document and fails must not truncate the
# original INDEX.md or leave stale private staging files in contexts/.
printf '# original preserved on failure\n' >"$INDEX_FILE"
chmod 640 "$INDEX_FILE"
index_rc=0
index_out=$(cd "$INDEX_FAKE" && INDEX_FIXTURE_FAIL=1 INDEX_EXPECTED_DIR="$INDEX_FAKE/contexts" PATH="$INDEX_FAKE/mock-bin:$PATH" just docs-index 2>&1) || index_rc=$?
if [ "$index_rc" -eq 0 ] || ! grep -qx '# original preserved on failure' "$INDEX_FILE" ||
  [ "$(index_mode)" != 640 ] || compgen -G "$INDEX_FAKE/contexts/.INDEX.md.*" >/dev/null; then
  echo "FAIL: docs-index generator error overwrote the original or left staging files (exit=$index_rc)" >&2
  printf '%s\n' "$index_out" >&2
  exit 1
fi
echo 'PASS: docs-index preserves the document and removes temp on generator failure'
