#!/usr/bin/env python3
"""Move a Stow conflict to a backup without traversing symlinked HOME parents.

All path components are opened relative to an O_NOFOLLOW directory descriptor.
Regular-file backups are detached copies; symlinks retain their link identity.
This protects backup contents from later writes through another open hard link.
"""
import os
import secrets
import stat
import sys


# Check platform support once. Tests deliberately intercept link(), but
# an unsupported dirfd/no-follow combination must always fail closed.
SECURE_LINK_SUPPORTED = (
    os.link in os.supports_dir_fd and os.link in os.supports_follow_symlinks
)


def _identity(entry):
    return (entry.st_dev, entry.st_ino, entry.st_mode)


def _version(entry):
    return (entry.st_size, entry.st_mtime_ns, entry.st_ctime_ns)


def _copy_regular(parent_fd, stage_fd, name, original):
    """Make a detached regular-file snapshot before claiming its backup name.

    A hard link is insufficient for a regular file: existing open writers or
    another user-owned hard link can mutate the supposed backup later.
    """
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    source_fd = os.open(name, flags, dir_fd=parent_fd)
    try:
        before = os.fstat(source_fd)
        if _identity(before) != _identity(original) or _version(before) != _version(
            original
        ):
            raise RuntimeError("source changed before backup copy")

        copy_fd = os.open(
            "snapshot",
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
            dir_fd=stage_fd,
        )
        try:
            remaining = before.st_size
            while remaining:
                chunk = os.read(source_fd, min(remaining, 1024 * 1024))
                if not chunk:
                    raise RuntimeError("source truncated during backup copy")
                view = memoryview(chunk)
                while view:
                    written = os.write(copy_fd, view)
                    if written <= 0:
                        raise OSError("short write during backup copy")
                    view = view[written:]
                remaining -= len(chunk)
            os.fchmod(copy_fd, stat.S_IMODE(before.st_mode))
            os.fsync(copy_fd)
        finally:
            os.close(copy_fd)
        after = os.fstat(source_fd)
        if _identity(after) != _identity(original) or _version(after) != _version(
            before
        ):
            raise RuntimeError("source changed during backup copy")
        return _version(before)
    finally:
        os.close(source_fd)


def _same_regular_contents(stage_fd):
    """Compare moved source and detached snapshot, without following links."""
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    source_fd = os.open("source", flags, dir_fd=stage_fd)
    snapshot_fd = os.open("snapshot", flags, dir_fd=stage_fd)
    try:
        while True:
            source_chunk = os.read(source_fd, 1024 * 1024)
            backup_chunk = os.read(snapshot_fd, 1024 * 1024)
            if source_chunk != backup_chunk:
                return False
            if not source_chunk:
                return True
    finally:
        os.close(snapshot_fd)
        os.close(source_fd)


def backup(home: str, target: str, timestamp: str) -> None:
    home = os.path.abspath(home)
    target = os.path.abspath(target)
    relative = os.path.relpath(target, home)
    if relative in (".", "..") or relative.startswith(".." + os.sep):
        raise ValueError("backup target escapes HOME")
    parts = relative.split(os.sep)
    if any(part in ("", ".", "..") for part in parts):
        raise ValueError("invalid backup target")

    if not hasattr(os, "O_NOFOLLOW") or not hasattr(os, "O_DIRECTORY"):
        raise RuntimeError("secure directory-descriptor traversal is unavailable")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    fd = os.open(home, flags)
    try:
        for component in parts[:-1]:
            child_fd = os.open(component, flags, dir_fd=fd)
            os.close(fd)
            fd = child_fd

        name = parts[-1]
        original = os.stat(name, dir_fd=fd, follow_symlinks=False)
        if stat.S_ISDIR(original.st_mode):
            raise ValueError("refusing to move an existing user directory")
        if not SECURE_LINK_SUPPORTED:
            raise RuntimeError("dirfd/no-follow hard links are unavailable")

        # A private dirfd confines final source removal and incomplete copies
        # to a new directory, even when the original HOME leaf is replaced.
        stage_name = f".{name}.stow-stage-{secrets.token_hex(16)}"
        os.mkdir(stage_name, mode=0o700, dir_fd=fd)
        stage_fd = None
        moved = False
        keep_stage = False
        regular = stat.S_ISREG(original.st_mode)
        copied_version = None
        try:
            stage_fd = os.open(stage_name, flags, dir_fd=fd)
            if regular:
                copied_version = _copy_regular(fd, stage_fd, name, original)

            # Claim the backup filename with a no-clobber hard link. Regular
            # files link the detached copy; symlinks retain their link text.
            base = f"{name}.backup.{timestamp}"
            suffix = 0
            while True:
                dest = base if suffix == 0 else f"{base}.{suffix}"
                try:
                    os.link(
                        "snapshot" if regular else name, dest,
                        src_dir_fd=stage_fd if regular else fd,
                        dst_dir_fd=fd, follow_symlinks=False,
                    )
                    break
                except FileExistsError:
                    suffix += 1

            try:
                backup_entry = os.stat(dest, dir_fd=fd, follow_symlinks=False)
                source_entry = os.stat(name, dir_fd=fd, follow_symlinks=False)
            except FileNotFoundError as exc:
                raise RuntimeError("source or backup changed during backup") from exc
            if _identity(source_entry) != _identity(original):
                raise RuntimeError("source changed during backup")
            if regular:
                snapshot_entry = os.stat(
                    "snapshot", dir_fd=stage_fd, follow_symlinks=False
                )
                if (
                    _identity(backup_entry) != _identity(snapshot_entry)
                    or _version(source_entry) != copied_version
                ):
                    raise RuntimeError("source or backup changed during backup")
            elif _identity(backup_entry) != _identity(original):
                raise RuntimeError("source or backup changed during backup")

            # Move the HOME entry to the private stage before removing it.
            os.rename(name, "source", src_dir_fd=fd, dst_dir_fd=stage_fd)
            moved = True
            staged = os.stat("source", dir_fd=stage_fd, follow_symlinks=False)
            changed = _identity(staged) != _identity(original)
            if regular and not changed:
                # Rename updates ctime on some filesystems. Check size, mtime
                # and full contents instead; a live writer that keeps writing
                # after this check cannot be atomically frozen portably.
                changed = (
                    (staged.st_size, staged.st_mtime_ns)
                    != (copied_version[0], copied_version[1])
                    or not _same_regular_contents(stage_fd)
                )
            if changed:
                # Restore without replacing a newly arrived user entry. Keep
                # the staged replacement even when restoration succeeds.
                try:
                    if not stat.S_ISDIR(staged.st_mode):
                        os.link(
                            "source", name, src_dir_fd=stage_fd,
                            dst_dir_fd=fd, follow_symlinks=False,
                        )
                except FileExistsError:
                    pass
                keep_stage = True
                raise RuntimeError(
                    "source changed during final move; replacement preserved at "
                    + os.path.join(os.path.dirname(target), stage_name, "source")
                )
            os.unlink("source", dir_fd=stage_fd)
        except OSError:
            keep_stage = moved
            raise
        finally:
            if stage_fd is not None:
                try:
                    if not keep_stage and regular:
                        try:
                            os.unlink("snapshot", dir_fd=stage_fd)
                        except FileNotFoundError:
                            pass
                finally:
                    os.close(stage_fd)
            if not keep_stage:
                os.rmdir(stage_name, dir_fd=fd)
    finally:
        os.close(fd)

if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: stow-safe-backup.py HOME TARGET TIMESTAMP")
    try:
        backup(*sys.argv[1:])
    except (OSError, ValueError, RuntimeError) as exc:
        raise SystemExit(f"❌ [Hard Block] 안전한 백업 이동 실패: {exc}")
