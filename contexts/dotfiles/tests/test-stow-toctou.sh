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
# atomic os.link, must still operate on the ORIGINAL opened directory, not external.
# Monkeypatch only syscall timing, not the kernel's dirfd/no-follow semantics.
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
original_link = os.link
swapped = [False]

def swap_parent_at_link(source, dest, *args, **kwargs):
    if kwargs.get("src_dir_fd") is not None and not swapped[0]:
        os.rename(home / ".config", home / ".config-original")
        os.symlink(external, home / ".config")
        swapped[0] = True
    return original_link(source, dest, *args, **kwargs)

os.link = swap_parent_at_link
try:
    helper.backup(str(home), str(home / ".config/app/config"), "fixed")
finally:
    os.link = original_link
assert swapped[0], "fault injection did not reach fd-based hard link"
assert (home / ".config").is_symlink()
assert (home / ".config-original/app/config.backup.fixed").read_text() == "original user\n"
assert (external / "app/config").read_text() == "external secret\n"
assert not (external / "app/config.backup.fixed").exists()
PY


# Competing backup creation between the old stat and rename used to be
# overwritten silently. Hard-link creation must instead choose a new suffix.
STOW_HELPER="$HELPER" STOW_TEST_ROOT="$TMP/dest-collision" "$REAL_PYTHON" - <<'PY'
import importlib.util
import os
from pathlib import Path

root = Path(os.environ["STOW_TEST_ROOT"])
root.mkdir()
(root / ".conf").write_text("original config\n")
spec = importlib.util.spec_from_file_location("stow_safe_backup", os.environ["STOW_HELPER"])
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
original_link = os.link
injected = [False]

def create_competing_backup(source, dest, *args, **kwargs):
    if kwargs.get("dst_dir_fd") is not None and not injected[0]:
        (root / ".conf.backup.fixed").write_text("valuable concurrent data\n")
        injected[0] = True
    return original_link(source, dest, *args, **kwargs)

os.link = create_competing_backup
try:
    helper.backup(str(root), str(root / ".conf"), "fixed")
finally:
    os.link = original_link

assert injected[0], "atomic collision was not injected"
assert (root / ".conf.backup.fixed").read_text() == "valuable concurrent data\n"
assert (root / ".conf.backup.fixed.1").read_text() == "original config\n"
assert not (root / ".conf").exists()
PY

# If the source entry changes before link(), do not unlink the replacement.
# The original data and the new value must both survive the failed operation.
STOW_HELPER="$HELPER" STOW_TEST_ROOT="$TMP/leaf-swap" "$REAL_PYTHON" - <<'PY'
import importlib.util
import os
from pathlib import Path

root = Path(os.environ["STOW_TEST_ROOT"])
root.mkdir()
(root / ".conf").write_text("original config\n")
spec = importlib.util.spec_from_file_location("stow_safe_backup", os.environ["STOW_HELPER"])
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
original_link = os.link
injected = [False]

def replace_leaf_before_link(source, dest, *args, **kwargs):
    if kwargs.get("src_dir_fd") is not None and not injected[0]:
        os.rename(root / ".conf", root / ".conf-original")
        (root / ".conf").write_text("new user config\n")
        injected[0] = True
    return original_link(source, dest, *args, **kwargs)

os.link = replace_leaf_before_link
try:
    try:
        helper.backup(str(root), str(root / ".conf"), "fixed")
    except RuntimeError as exc:
        assert "changed during backup" in str(exc)
    else:
        raise AssertionError("source replacement was not blocked")
finally:
    os.link = original_link

assert injected[0], "source replacement was not injected"
assert (root / ".conf-original").read_text() == "original config\n"
assert (root / ".conf").read_text() == "new user config\n"
PY

# Broken symlinks must remain symlinks after backup; a pre-existing broken
# symlink at the destination also occupies its name and cannot be overwritten.
STOW_HELPER="$HELPER" STOW_TEST_ROOT="$TMP/symlink-collision" "$REAL_PYTHON" - <<'PY'
import importlib.util
import os
from pathlib import Path

root = Path(os.environ["STOW_TEST_ROOT"])
root.mkdir()
(root / ".link").symlink_to("old-missing-target")
(root / ".link.backup.fixed").symlink_to("foreign-missing-target")
spec = importlib.util.spec_from_file_location("stow_safe_backup", os.environ["STOW_HELPER"])
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
helper.backup(str(root), str(root / ".link"), "fixed")
assert not (root / ".link").is_symlink()
assert os.readlink(root / ".link.backup.fixed") == "foreign-missing-target"
assert os.readlink(root / ".link.backup.fixed.1") == "old-missing-target"
PY

echo 'PASS: parent swaps, atomic destination collisions, leaf swaps and symlinks are safe'
