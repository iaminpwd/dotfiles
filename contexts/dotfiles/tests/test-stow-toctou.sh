#!/usr/bin/env bash
# Deterministically swap a HOME parent for an external symlink at backup time.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
BACKUP="$ROOT/bin/utils/stow-backup.sh"
HELPER="$ROOT/bin/utils/stow-safe-backup.py"
REAL_PYTHON=$(command -v python3)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The package preflight sees normal directories. Right before the actual
# backup helper runs, another process substitutes a foreign directory symlink.
CASE="$TMP/before-open"
mkdir -p "$CASE/stow/pkg/.config/app" "$CASE/home/.config/app" \
  "$CASE/external/app" "$CASE/fake-bin"
printf 'managed\n' >"$CASE/stow/pkg/.config/app/config"
printf 'original user\n' >"$CASE/home/.config/app/config"
printf 'external secret\n' >"$CASE/external/app/config"
cat >"$CASE/fake-bin/python3" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
if [ ! -e "$STOW_SWAP_MARKER" ]; then
  : >"$STOW_SWAP_MARKER"
  /bin/mv "$STOW_TEST_HOME/.config" "$STOW_TEST_HOME/.config-original"
  ln -s "$STOW_EXTERNAL" "$STOW_TEST_HOME/.config"
fi
exec "$STOW_REAL_PYTHON" "$@"
SHIM
chmod +x "$CASE/fake-bin/python3"
status=0
STOW_TEST_HOME="$CASE/home" STOW_EXTERNAL="$CASE/external" \
  STOW_SWAP_MARKER="$CASE/swapped" STOW_REAL_PYTHON="$REAL_PYTHON" \
  PATH="$CASE/fake-bin:$PATH" HOME="$CASE/home" \
  bash "$BACKUP" pkg "$CASE/stow" "$CASE/home" >"$CASE/out" 2>&1 || status=$?
if [ "$status" -eq 0 ] ||
  ! grep -qF '[Hard Block]' "$CASE/out" ||
  [ ! -L "$CASE/home/.config" ] ||
  [ "$(readlink "$CASE/home/.config")" != "$CASE/external" ] ||
  ! grep -qx 'original user' "$CASE/home/.config-original/app/config" ||
  ! grep -qx 'external secret' "$CASE/external/app/config" ||
  [ -e "$CASE/external/app/config.backup.fixed" ]; then
  cat "$CASE/out"
  echo 'FAIL: parent changed before open: external user path was modified'
  exit 1
fi

# A later swap, after O_NOFOLLOW opened the parent fd but immediately before
# os.rename, must still operate on the ORIGINAL opened directory, not external.
# Monkeypatch only the timing of the real rename syscall, not its fd semantics.
STOW_HELPER="$HELPER" STOW_TEST_ROOT="$TMP/after-open" "$REAL_PYTHON" - <<'PY'
import importlib.util
import os
from pathlib import Path

root = Path(os.environ["STOW_TEST_ROOT"])
home, external = root / "home", root / "external"
(home / ".config/app").mkdir(parents=True)
(external / "app").mkdir(parents=True)
(home / ".config/app/config").write_text("original user\n")
(external / "app/config").write_text("external secret\n")
spec = importlib.util.spec_from_file_location(
    "stow_safe_backup", os.environ["STOW_HELPER"]
)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
original_rename = os.rename
swapped = [False]

def swap_parent_at_rename(source, dest, *args, **kwargs):
    if kwargs.get("src_dir_fd") is not None and not swapped[0]:
        original_rename(home / ".config", home / ".config-original")
        os.symlink(external, home / ".config")
        swapped[0] = True
    return original_rename(source, dest, *args, **kwargs)

os.rename = swap_parent_at_rename
try:
    helper.backup(str(home), str(home / ".config/app/config"), "fixed")
finally:
    os.rename = original_rename
assert swapped[0], "fault injection did not reach fd-based rename"
assert (home / ".config").is_symlink()
assert (home / ".config-original/app/config.backup.fixed").read_text() == "original user\n"
assert (external / "app/config").read_text() == "external secret\n"
assert not (external / "app/config.backup.fixed").exists()
PY

echo 'PASS: parent symlink swaps before/after opened dirfd cannot redirect backups'
