#!/usr/bin/env python3
"""Move a Stow conflict to a backup without traversing symlinked HOME parents.

All path components are opened relative to an O_NOFOLLOW directory descriptor.
This matters if another process swaps a checked directory for a foreign symlink
between the backup script's preflight and the eventual rename syscall.
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


def backup(home: str, target: str, timestamp: str) -> None:
    home = os.path.abspath(home)
    target = os.path.abspath(target)
    relative = os.path.relpath(target, home)
    if relative in (".", "..") or relative.startswith(".." + os.sep):
        raise ValueError("backup target escapes HOME")
    parts = relative.split(os.sep)
    if any(part in ("", ".", "..") for part in parts):
        raise ValueError("invalid backup target")

    # Require O_NOFOLLOW: never silently fall back to path-based traversal.
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
        current = os.stat(name, dir_fd=fd, follow_symlinks=False)
        if stat.S_ISDIR(current.st_mode):
            raise ValueError("refusing to move an existing user directory")

        # A check-then-rename can overwrite a valuable file installed at
        # dest by another process after the check. Claim the backup filename
        # atomically with a no-follow hard link (EEXIST never overwrites).
        # Both names are resolved through the same verified parent dirfd.
        if not SECURE_LINK_SUPPORTED:
            raise RuntimeError("dirfd/no-follow hard links are unavailable")
        base = f"{name}.backup.{timestamp}"
        suffix = 0
        while True:
            dest = base if suffix == 0 else f"{base}.{suffix}"
            try:
                os.link(
                    name, dest, src_dir_fd=fd, dst_dir_fd=fd, follow_symlinks=False
                )
                break
            except FileExistsError:
                suffix += 1

        # A concurrent source replacement before the hard-link syscall must
        # not be removed. If identity changed, retain both names and stop;
        # an extra hard link on failure is safer than deleting user content.
        original = (current.st_dev, current.st_ino, current.st_mode)
        try:
            backup_entry = os.stat(dest, dir_fd=fd, follow_symlinks=False)
            source_entry = os.stat(name, dir_fd=fd, follow_symlinks=False)
        except FileNotFoundError as exc:
            raise RuntimeError("source or backup changed during backup") from exc
        if any(
            (entry.st_dev, entry.st_ino, entry.st_mode) != original
            for entry in (source_entry, backup_entry)
        ):
            raise RuntimeError("source or backup changed during backup")
        # A checked HOME filename can be replaced before unlink(). Move the
        # final entry into a private directory first: if it is a concurrent
        # replacement, preserve it for recovery rather than deleting it.
        stage_name = f".{name}.stow-stage-{secrets.token_hex(16)}"
        os.mkdir(stage_name, mode=0o700, dir_fd=fd)
        stage_fd = None
        moved = False
        keep_stage = False
        try:
            stage_fd = os.open(stage_name, flags, dir_fd=fd)
            os.rename(name, "source", src_dir_fd=fd, dst_dir_fd=stage_fd)
            moved = True
            staged = os.stat("source", dir_fd=stage_fd, follow_symlinks=False)
            if (staged.st_dev, staged.st_ino, staged.st_mode) != original:
                # Restore only when the source name is still vacant. Retain
                # the staged copy even after restoring, to avoid losing user
                # data to another concurrent replacement of the HOME name.
                try:
                    if not stat.S_ISDIR(staged.st_mode):
                        os.link(
                            "source", name, src_dir_fd=stage_fd,
                            dst_dir_fd=fd, follow_symlinks=False
                        )
                except FileExistsError:
                    pass
                keep_stage = True
                raise RuntimeError(
                    "source changed during final move; replacement preserved at "
                    + os.path.join(os.path.dirname(target), stage_name, "source")
                )
            # This entry is in our private staging directory, not at a
            # mutable user pathname. The original inode remains at dest.
            os.unlink("source", dir_fd=stage_fd)
        except OSError:
            # If move completed, retain the entry on later I/O failures.
            keep_stage = moved
            raise
        finally:
            if stage_fd is not None:
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
