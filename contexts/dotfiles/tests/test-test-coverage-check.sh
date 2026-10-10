#!/usr/bin/env bash
# Registration checker contract: dynamic suite discovery and visible SKIP warnings.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0

ok() {
  printf 'PASS: %s\n' "$1"
  PASS=$((PASS + 1))
}
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

new_repo() {
  local repo=$1
  mkdir -p "$repo/bin/linters" "$repo/bin/lib" "$repo/contexts/fake/tests" "$repo/tests/lib"
  cp "$ROOT/bin/linters/test-coverage-check.sh" "$repo/bin/linters/"
  cp "$ROOT/bin/lib/script-init.sh" "$repo/bin/lib/"
  cp "$ROOT/tests/lib/run-domain-tests.sh" "$repo/tests/lib/"
  cat >"$repo/contexts/fake/tests/run.sh" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
export QUIET=0
tdir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$tdir/../../.." && pwd)
exec bash "$repo/tests/lib/run-domain-tests.sh" "$tdir" "$@"
RUNNER
}

check() {
  local repo=$1 rc=0
  (cd "$repo" && QUIET=0 bash "$repo/bin/linters/test-coverage-check.sh") >"$TMP/out" 2>&1 || rc=$?
  return "$rc"
}

# Domains with no separate test files may still use a scenario-based run.sh.
BASE="$TMP/empty"
new_repo "$BASE"
check "$BASE" || fail "empty domain checker"
ok "empty domain checker"

# BSD readlink without -f, invoked through a symlink with unrelated CWD.
BSD="$TMP/bsd"
new_repo "$BSD"
ln -s bin/linters/test-coverage-check.sh "$BSD/check"
mkdir -p "$BSD/fake-bin"
cat >"$BSD/fake-bin/readlink" <<'READLINK'
#!/bin/sh
if [ "${1:-}" = -f ]; then exit 91; fi
exec /usr/bin/readlink "$@"
READLINK
chmod +x "$BSD/fake-bin/readlink"
(cd / && PATH="$BSD/fake-bin:$PATH" bash "$BSD/check" >"$TMP/bsd-out" 2>&1) || fail "BSD readlink compatibility"
ok "BSD readlink compatibility"

# A newly added test must be listed automatically. --list must not execute it.
NEW="$TMP/new"
new_repo "$NEW"
cat >"$NEW/contexts/fake/tests/test-new.sh" <<'TEST'
#!/usr/bin/env bash
echo RAN_NEW_TEST
TEST
check "$NEW" || fail "automatic discovery checker"
listed=$(bash "$NEW/contexts/fake/tests/run.sh" --list)
[ "$listed" = "$NEW/contexts/fake/tests/test-new.sh" ] || fail "automatic --list output"
[[ "$listed" != *RAN_NEW_TEST* ]] || fail "--list executed test"
out=$(bash "$NEW/contexts/fake/tests/run.sh") || fail "automatic new test execution"
[[ "$out" == *RAN_NEW_TEST* ]] || fail "new test was not executed"
ok "new file discovered, listed and executed"

# Support historical test_*.sh naming in prompt-architect.
cat >"$NEW/contexts/fake/tests/test_underscore.sh" <<'TEST'
#!/usr/bin/env bash
echo RAN_UNDERSCORE_TEST
TEST
check "$NEW" || fail "underscore checker"
listed=$(bash "$NEW/contexts/fake/tests/run.sh" --list)
[[ "$listed" == *test_underscore.sh* ]] || fail "underscore discovery"
out=$(bash "$NEW/contexts/fake/tests/run.sh") || fail "underscore execution"
[[ "$out" == *RAN_UNDERSCORE_TEST* ]] || fail "underscore not executed"
ok "test_*.sh discovered"

# Missing domain runner must hard-fail.
MISSING="$TMP/missing"
new_repo "$MISSING"
printf '#!/usr/bin/env bash\n' >"$MISSING/contexts/fake/tests/test-orphan.sh"
rm "$MISSING/contexts/fake/tests/run.sh"
if check "$MISSING" || ! grep -qF '진입점' "$TMP/out"; then
  fail "missing runner should block"
fi
ok "missing runner blocks"

# A broken runner which silently omits a file must not pass the checker.
BROKEN="$TMP/broken"
new_repo "$BROKEN"
printf '#!/usr/bin/env bash\n' >"$BROKEN/contexts/fake/tests/test-orphan.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$BROKEN/contexts/fake/tests/run.sh"
if check "$BROKEN" || ! grep -qF '일치하지 않습니다' "$TMP/out"; then
  fail "silent list omission should block"
fi
ok "runner omission blocks"

# A failed test must not hide later cases.
printf '#!/usr/bin/env bash\necho FAIL_MARKER\nexit 7\n' >"$NEW/contexts/fake/tests/test-fail.sh"
rc=0
out=$(bash "$NEW/contexts/fake/tests/run.sh" 2>&1) || rc=$?
[ "$rc" -ne 0 ] && [[ "$out" == *FAIL_MARKER* && "$out" == *RAN_NEW_TEST* ]] ||
  fail "failure aggregation"
ok "failed script does not skip later scripts"

# Empty suite may not silently succeed.
if bash "$BASE/contexts/fake/tests/run.sh" >"$TMP/empty-out" 2>&1; then
  fail "empty suite fail-closed"
fi
grep -qF '발견된 회귀 테스트가 없습니다' "$TMP/empty-out" || fail "empty error message"
ok "empty suite blocks"

# Construct the literal at runtime so this test file does not trigger its
# own checker. An invisible SKIP must block; a prefixed warning must pass.
SKIP_REPO="$TMP/skip"
new_repo "$SKIP_REPO"
{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "  %s  tool unavailable"\n' "SKIP"
} \
  >"$SKIP_REPO/contexts/fake/tests/test-skip.sh"
if check "$SKIP_REPO" || ! grep -qF '압축 필터' "$TMP/out"; then
  fail "invisible SKIP should block"
fi
ok "invisible SKIP blocks"

{
  printf '#!/usr/bin/env bash\n'
  printf 'echo "[WARNING] %s tool unavailable"\n' "SKIP"
} \
  >"$SKIP_REPO/contexts/fake/tests/test-skip.sh"
check "$SKIP_REPO" || fail "visible warning should pass"
ok "visible SKIP warning passes"

echo "$PASS/$PASS passed"
