#!/usr/bin/env bash
# Deterministically swap a HOME parent for an external symlink at backup time.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
BACKUP="$ROOT/bin/utils/stow-backup.sh"
HELPER="$ROOT/bin/utils/stow-safe-backup.py"
# Prefer the system interpreter for the syscall fixture: HOME changes here can
# make mise shims reinstall Python and depend on GitHub attestations mid-test.
# Fallback supports hosts that only provide Python via PATH/mise.
if [ -x /usr/bin/python3 ]; then
  REAL_PYTHON=/usr/bin/python3
else
  REAL_PYTHON=$(python3 -c 'import os, sys; print(os.path.realpath(sys.executable))')
fi
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

# A replacement installed after inode validation, immediately before the
# final source move, must not be deleted. Retain its staged copy even if a
# third writer also claims the original pathname before safe restoration.
STOW_HELPER="$HELPER" STOW_TEST_ROOT="$TMP/final-move" "$REAL_PYTHON" - <<'PY'
import importlib.util
import os
from pathlib import Path

root = Path(os.environ["STOW_TEST_ROOT"])
root.mkdir()
spec = importlib.util.spec_from_file_location("stow_safe_backup", os.environ["STOW_HELPER"])
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

for kind in ("file", "symlink"):
    for race in ("normal", "replace", "replace-again"):
        home = root / f"{kind}-{race}"
        home.mkdir()
        source = home / ".conf"
        if kind == "file":
            source.write_text("original A\n")
        else:
            source.symlink_to("old-missing-A")

        real_rename, real_link = os.rename, os.link
        replaced = [False]

        def swap_before_final_move(src, dst, *args, **kwargs):
            if src == ".conf" and kwargs.get("src_dir_fd") is not None and not replaced[0]:
                incoming = home / "incoming"
                if kind == "file":
                    incoming.write_text("new user B\n")
                else:
                    incoming.symlink_to("new-missing-B")
                os.replace(incoming, source)
                replaced[0] = True
            return real_rename(src, dst, *args, **kwargs)

        def claim_source_during_restore(src, dst, *args, **kwargs):
            if src == "source" and dst == ".conf" and race == "replace-again":
                if kind == "file":
                    source.write_text("newest user C\n")
                else:
                    source.symlink_to("new-missing-C")
            return real_link(src, dst, *args, **kwargs)

        if race != "normal":
            os.rename = swap_before_final_move
        if race == "replace-again":
            os.link = claim_source_during_restore
        error = None
        try:
            try:
                helper.backup(str(home), str(source), "fixed")
            except RuntimeError as exc:
                error = str(exc)
        finally:
            os.rename, os.link = real_rename, real_link

        backup = home / ".conf.backup.fixed"
        if kind == "file":
            assert backup.read_text() == "original A\n"
        else:
            assert os.readlink(backup) == "old-missing-A"
        stages = list(home.glob("..conf.stow-stage-*"))
        if race == "normal":
            assert error is None and not stages and not os.path.lexists(source)
            continue

        assert replaced[0] and error and "source changed during final move" in error
        assert len(stages) == 1, (kind, race, stages)
        saved = stages[0] / "source"
        if kind == "file":
            assert saved.read_text() == "new user B\n"
            assert source.read_text() == (
                "newest user C\n" if race == "replace-again" else "new user B\n"
            )
        else:
            assert os.readlink(saved) == "new-missing-B"
            assert os.readlink(source) == (
                "new-missing-C" if race == "replace-again" else "new-missing-B"
            )
PY

# If removal of the verified private staging entry fails, preserve its
# contents and the original backup instead of blindly cleaning up.
STOW_HELPER="$HELPER" STOW_TEST_ROOT="$TMP/final-move-io" "$REAL_PYTHON" - <<'PY'
import importlib.util
import os
from pathlib import Path

home = Path(os.environ["STOW_TEST_ROOT"])
home.mkdir()
(home / ".conf").write_text("original A\n")
spec = importlib.util.spec_from_file_location("stow_safe_backup", os.environ["STOW_HELPER"])
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
real_unlink = os.unlink

def fail_staging_unlink(name, *args, **kwargs):
    if name == "source" and kwargs.get("dir_fd") is not None:
        raise OSError(5, "injected staging EIO")
    return real_unlink(name, *args, **kwargs)

os.unlink = fail_staging_unlink
try:
    try:
        helper.backup(str(home), str(home / ".conf"), "fixed")
    except OSError as exc:
        assert exc.errno == 5
    else:
        raise AssertionError("staging unlink failure must hard block")
finally:
    os.unlink = real_unlink

assert (home / ".conf.backup.fixed").read_text() == "original A\n"
stages = list(home.glob("..conf.stow-stage-*"))
assert len(stages) == 1
assert (stages[0] / "source").read_text() == "original A\n"
PY

echo 'PASS: final move preserves concurrent user files, symlinks and staging I/O failures'

# Regular-file hard links share mutable inode contents. A backup must instead
# hold a separate snapshot, even if a writer has kept the old source fd open.
STOW_HELPER="$HELPER" STOW_TEST_ROOT="$TMP/detached-backup" "$REAL_PYTHON" - <<'PY'
import importlib.util
import os
import stat
from pathlib import Path

root = Path(os.environ["STOW_TEST_ROOT"])
root.mkdir()
spec = importlib.util.spec_from_file_location("stow_safe_backup", os.environ["STOW_HELPER"])
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

# Direct old open fd: the source disappears, but the writer can still write.
home = root / "open-writer"
home.mkdir()
source = home / ".conf"
source.write_bytes(b"original A\n")
source.chmod(0o600)
writer = os.open(source, os.O_RDWR)
try:
    helper.backup(str(home), str(source), "fixed")
    backup = home / ".conf.backup.fixed"
    assert not source.exists()
    assert backup.read_bytes() == b"original A\n"
    assert stat.S_IMODE(backup.stat().st_mode) == 0o600
    assert os.fstat(writer).st_ino != backup.stat().st_ino
    os.lseek(writer, 0, os.SEEK_SET)
    os.write(writer, b"changed! B\n")
    os.fsync(writer)
    assert backup.read_bytes() == b"original A\n"
finally:
    os.close(writer)

# Another user-owned hard link to the source remains writable after backup.
home = root / "second-link"
home.mkdir()
source = home / ".conf"
source.write_bytes(b"original A\n")
peer = home / "shared-peer"
os.link(source, peer)
helper.backup(str(home), str(source), "fixed")
backup = home / ".conf.backup.fixed"
peer.write_bytes(b"updated B!\n")
assert backup.read_bytes() == b"original A\n"
assert backup.stat().st_ino != peer.stat().st_ino
assert peer.read_bytes() == b"updated B!\n"

# A source change while making the copy must abort before claiming a backup
# filename, without deleting either the original pathname or its new content.
home = root / "mid-copy-write"
home.mkdir()
source = home / ".conf"
source.write_bytes(b"original A\n")
real_read = os.read
swapped = [False]

def modify_during_copy(fd, size):
    chunk = real_read(fd, size)
    if not swapped[0] and chunk == b"original A\n":
        source.write_bytes(b"changed! B\n")
        swapped[0] = True
    return chunk

os.read = modify_during_copy
try:
    try:
        helper.backup(str(home), str(source), "fixed")
    except RuntimeError as exc:
        assert "changed during backup copy" in str(exc)
    else:
        raise AssertionError("in-place write during copy must hard block")
finally:
    os.read = real_read
assert swapped[0]
assert source.read_bytes() == b"changed! B\n"
assert not (home / ".conf.backup.fixed").exists()
assert not list(home.glob("..conf.stow-stage-*"))

# A leaf replacement after snapshot creation must preserve both the old
# independent snapshot and the newly installed user file.
home = root / "after-copy-replace"
home.mkdir()
source = home / ".conf"
source.write_bytes(b"original A\n")
real_link = os.link
swapped = [False]

def change_before_backup_link(src, dst, *args, **kwargs):
    if src == "snapshot" and not swapped[0]:
        os.replace(source, home / "saved-A")
        source.write_bytes(b"new user B\n")
        swapped[0] = True
    return real_link(src, dst, *args, **kwargs)

os.link = change_before_backup_link
try:
    try:
        helper.backup(str(home), str(source), "fixed")
    except RuntimeError as exc:
        assert "source changed during backup" in str(exc)
    else:
        raise AssertionError("replacement before backup hard link must hard block")
finally:
    os.link = real_link
assert swapped[0]
assert source.read_bytes() == b"new user B\n"
assert (home / "saved-A").read_bytes() == b"original A\n"
assert (home / ".conf.backup.fixed").read_bytes() == b"original A\n"

# Symlinks must continue to back up as symlinks, including broken targets.
home = root / "broken-link"
home.mkdir()
source = home / ".link"
source.symlink_to("never-existed")
helper.backup(str(home), str(source), "fixed")
assert os.readlink(home / ".link.backup.fixed") == "never-existed"
PY

echo 'PASS: regular-file snapshots remain detached from open writers and hard-link peers'

# A failed detached copy must never remove user content or overwrite an older
# backup. Exercise real filesystem calls with just one injected syscall error.
# Failures after source movement must keep the published copy for recovery.
STOW_HELPER="$HELPER" STOW_TEST_ROOT="$TMP/partial-copy-failures" "$REAL_PYTHON" - <<'PY'
import errno
import importlib.util
import os
from pathlib import Path

root = Path(os.environ["STOW_TEST_ROOT"])
root.mkdir()
spec = importlib.util.spec_from_file_location("stow_safe_backup", os.environ["STOW_HELPER"])
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

cases = (
    ("read-eio", "read", errno.EIO),
    ("write-enospc", "write", errno.ENOSPC),
    ("fsync-eio", "fsync", errno.EIO),
    ("chmod-eperm", "fchmod", errno.EPERM),
    ("snapshot-open-eacces", "open", errno.EACCES),
    ("backup-link-eperm", "link", errno.EPERM),
    ("final-rename-eio", "rename", errno.EIO),
    ("source-unlink-eio", "unlink", errno.EIO),
    ("snapshot-unlink-eio", "unlink", errno.EIO),
)

for label, operation, error_number in cases:
    home = root / label
    home.mkdir()
    source = home / ".conf"
    original = b"valuable user content\n"
    source.write_bytes(original)
    existing = home / ".conf.backup.fixed"
    existing.write_bytes(b"existing valuable backup\n")
    original_call = getattr(os, operation)
    injection = [False]
    write_partial = [False]

    def intercept(*args, **kwargs):
        match = (
            (operation == "read" and label == "read-eio")
            or (operation == "write" and label == "write-enospc")
            or (operation == "fsync" and label == "fsync-eio")
            or (operation == "fchmod" and label == "chmod-eperm")
            or (operation == "open" and args[0] == "snapshot")
            or (operation == "link" and args[0] == "snapshot")
            or (operation == "rename" and args[:2] == (".conf", "source"))
            or (operation == "unlink" and (
                (label == "source-unlink-eio" and args[0] == "source")
                or (label == "snapshot-unlink-eio" and args[0] == "snapshot")
            ))
        )
        if match and not injection[0]:
            if label == "write-enospc" and not write_partial[0]:
                write_partial[0] = True
                return original_call(args[0], args[1][:3])
            injection[0] = True
            raise OSError(error_number, os.strerror(error_number))
        return original_call(*args, **kwargs)

    setattr(os, operation, intercept)
    try:
        try:
            helper.backup(str(home), str(source), "fixed")
        except OSError as exc:
            assert exc.errno == error_number, (label, exc)
        else:
            raise AssertionError(f"{label}: backup unexpectedly succeeded")
    finally:
        setattr(os, operation, original_call)

    assert injection[0], f"{label}: fault injection did not run"
    assert existing.read_bytes() == b"existing valuable backup\n", label
    backups = list(home.glob(".conf.backup.fixed.*"))
    stages = list(home.glob("..conf.stow-stage-*"))
    saved = [source] if source.exists() else []
    saved += backups
    for stage in stages:
        saved.extend(stage.iterdir())
    assert any(path.is_file() and path.read_bytes() == original for path in saved), (
        label, saved
    )

    if source.exists():
        # A retry must not overwrite either the timestamp collision or a
        # backup already published before the injected syscall failed.
        previous = {path: path.read_bytes() for path in [existing, *backups]}
        helper.backup(str(home), str(source), "fixed")
        assert not source.exists(), label
        assert all(path.read_bytes() == value for path, value in previous.items()), label
        assert any(
            path.read_bytes() == original
            for path in home.glob(".conf.backup.fixed.*")
        ), label
    else:
        # No automatic rollback after final source movement; the published
        # copy, rather than a mutable source name, is the recovery artifact.
        assert backups and any(path.read_bytes() == original for path in backups), label

print("PASS: injected partial-copy failures preserve user data and retry safely")
PY

# Some filesystems (network shares, FUSE, restricted mounts) cannot publish
# hard links. Never fall back to a path-based rename/copy that could clobber
# an existing backup or remove the only user file. Use injected errno rather
# than requiring a privileged mount or touching the runner's actual HOME.
STOW_HELPER="$HELPER" STOW_TEST_ROOT="$TMP/filesystem-compat" "$REAL_PYTHON" - <<'PY'
import errno
import importlib.util
import os
from pathlib import Path

root = Path(os.environ["STOW_TEST_ROOT"])
root.mkdir()
spec = importlib.util.spec_from_file_location("stow_safe_backup", os.environ["STOW_HELPER"])
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

cases = (
    ("file-link-enotsup", "link", errno.ENOTSUP, "regular"),
    ("file-link-eperm", "link", errno.EPERM, "regular"),
    ("file-link-emlink", "link", errno.EMLINK, "regular"),
    ("file-link-exdev", "link", errno.EXDEV, "regular"),
    ("file-link-erofs", "link", errno.EROFS, "regular"),
    ("file-link-enospc", "link", errno.ENOSPC, "regular"),
    ("symlink-link-enotsup", "link", errno.ENOTSUP, "symlink"),
    ("symlink-link-eperm", "link", errno.EPERM, "symlink"),
    ("stage-mkdir-erofs", "mkdir", errno.EROFS, "regular"),
    ("stage-mkdir-eacces", "mkdir", errno.EACCES, "regular"),
    ("stage-open-eacces", "open-stage", errno.EACCES, "regular"),
    ("stage-open-eloop", "open-stage", errno.ELOOP, "regular"),
    ("source-open-eacces", "open-source", errno.EACCES, "regular"),
    ("home-open-eacces", "open-home", errno.EACCES, "regular"),
    ("nested-parent-eacces", "open-parent", errno.EACCES, "regular"),
)
for label, operation, expected_errno, kind in cases:
    home = root / label
    home.mkdir()
    target_parent = home
    if operation == "open-parent":
        target_parent = home / ".config"
        target_parent.mkdir()
    source = target_parent / ".conf"
    backup = target_parent / ".conf.backup.fixed"
    if kind == "symlink":
        source.symlink_to("missing-original-user-target")
    else:
        source.write_bytes(b"valuable original user file\n")
    backup.write_bytes(b"valuable prior backup\n")
    syscall = "open" if operation.startswith("open-") else operation
    original_call = getattr(os, syscall)
    injected = [False]

    def fail_selected_call(*args, **kwargs):
        leaf = args[0] if args else None
        if operation == "link":
            match = (
                len(args) >= 2 and
                args[1].startswith(".conf.backup.fixed") and
                kwargs.get("dst_dir_fd") is not None
            )
        elif operation == "mkdir":
            match = (
                isinstance(leaf, str) and
                leaf.startswith("..conf.stow-stage-") and
                kwargs.get("dir_fd") is not None
            )
        elif operation == "open-stage":
            match = (
                isinstance(leaf, str) and
                leaf.startswith("..conf.stow-stage-") and
                kwargs.get("dir_fd") is not None
            )
        elif operation == "open-source":
            match = leaf == ".conf" and kwargs.get("dir_fd") is not None
        elif operation == "open-parent":
            match = leaf == ".config" and kwargs.get("dir_fd") is not None
        else:
            match = leaf == str(home) and kwargs.get("dir_fd") is None
        if match and not injected[0]:
            injected[0] = True
            raise OSError(expected_errno, os.strerror(expected_errno))
        return original_call(*args, **kwargs)

    setattr(os, syscall, fail_selected_call)
    try:
        try:
            helper.backup(str(home), str(source), "fixed")
        except OSError as exc:
            assert exc.errno == expected_errno, (label, exc)
        else:
            raise AssertionError(f"{label}: unsupported operation silently succeeded")
    finally:
        setattr(os, syscall, original_call)

    assert injected[0], f"{label}: fault injection did not execute"
    assert backup.read_bytes() == b"valuable prior backup\n", label
    assert list(target_parent.glob(".conf.backup.fixed.*")) == [], label
    assert list(target_parent.glob("..conf.stow-stage-*")) == [], label
    if kind == "symlink":
        assert os.readlink(source) == "missing-original-user-target", label
    else:
        assert source.read_bytes() == b"valuable original user file\n", label

# If this Python build cannot provide no-follow/dirfd hard links, fail before
# any attempt to stage or delete user content. Do not weaken the capability
# gate to support restricted filesystems.
home = root / "no-secure-link-capability"
home.mkdir()
source = home / ".conf"
source.write_bytes(b"valuable original user file\n")
prior = home / ".conf.backup.fixed"
prior.write_bytes(b"valuable prior backup\n")
supported = helper.SECURE_LINK_SUPPORTED
helper.SECURE_LINK_SUPPORTED = False
try:
    try:
        helper.backup(str(home), str(source), "fixed")
    except RuntimeError as exc:
        assert "dirfd/no-follow hard links are unavailable" in str(exc)
    else:
        raise AssertionError("missing secure link support must block")
finally:
    helper.SECURE_LINK_SUPPORTED = supported
assert source.read_bytes() == b"valuable original user file\n"
assert prior.read_bytes() == b"valuable prior backup\n"
assert not list(home.glob("..conf.stow-stage-*"))

# Exercise a real POSIX permission denial as well (skipped under root,
# whose DAC override would make a read-only directory writable).
if hasattr(os, "geteuid") and os.geteuid() != 0:
    home = root / "real-directory-permission"
    home.mkdir()
    source = home / ".conf"
    source.write_bytes(b"valuable original user file\n")
    prior = home / ".conf.backup.fixed"
    prior.write_bytes(b"valuable prior backup\n")
    home.chmod(0o500)
    try:
        try:
            helper.backup(str(home), str(source), "fixed")
        except PermissionError:
            pass
        else:
            raise AssertionError("read-only HOME directory must hard block")
    finally:
        home.chmod(0o700)
    assert source.read_bytes() == b"valuable original user file\n"
    assert prior.read_bytes() == b"valuable prior backup\n"
    assert not list(home.glob("..conf.stow-stage-*"))

print("PASS: unsupported hard links, read-only and permission errors preserve user content")
PY

echo 'PASS: parent swaps, atomic destination collisions, leaf swaps and symlinks are safe'


# Round 21: the opened Stow root can be renamed away after source validation.
# An fd anchored to the moved directory still sees the ORIGINAL source, but
# the new HOME symlink text resolves through the REPLACEMENT Stow root.
# Detect it rather than reporting a successful installation of another file.
STOW_INSTALLER="$ROOT/bin/utils/stow-safe-install.py" \
  STOW_TEST_ROOT="$TMP/source-root-relocation" "$REAL_PYTHON" - <<'PY'
import importlib.util
import os
from pathlib import Path

root = Path(os.environ["STOW_TEST_ROOT"])
stow, home, moved = root / "stow", root / "home", root / "moved-stow"
(stow / "demo").mkdir(parents=True)
home.mkdir()
(stow / "demo/.managed").write_bytes(b"trusted source A\n")
spec = importlib.util.spec_from_file_location(
    "stow_safe_install", os.environ["STOW_INSTALLER"]
)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

real_symlink = os.symlink
injected = [False]

def move_root_at_symlink(target, name, *args, **kwargs):
    if kwargs.get("dir_fd") is not None and not injected[0]:
        injected[0] = True
        os.rename(stow, moved)
        (stow / "demo").mkdir(parents=True)
        (stow / "demo/.managed").write_bytes(b"replacement source B\n")
    return real_symlink(target, name, *args, **kwargs)

os.symlink = move_root_at_symlink
try:
    try:
        helper.install(str(stow), "demo", str(home))
    except RuntimeError as exc:
        assert "Stow source root moved" in str(exc), exc
    else:
        raise AssertionError("renamed Stow root incorrectly accepted as trusted")
finally:
    os.symlink = real_symlink

assert injected[0], "root relocation was not injected at symlinkat"
assert (moved / "demo/.managed").read_bytes() == b"trusted source A\n"
assert (stow / "demo/.managed").read_bytes() == b"replacement source B\n"
PY
echo 'PASS: moved Stow root cannot silently validate a replacement source'
