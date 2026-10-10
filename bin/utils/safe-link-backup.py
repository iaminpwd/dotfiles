#!/usr/bin/env python3
"""Claim a non-clobbering backup name for files, symlinks and directories.

The source and destination live in the same pinned parent directory. Link
creation / mkdir atomically claims the backup name, avoiding check-then-mv
overwrites when another process concurrently creates that name.
"""

import os
import secrets
import stat
import sys


def _identity(entry):
    return entry.st_dev, entry.st_ino, stat.S_IFMT(entry.st_mode)


def backup(target, timestamp):
    parent, name = os.path.split(os.path.abspath(target))
    if not name or name in (".", ".."):
        raise ValueError("invalid backup target")
    if os.link not in os.supports_dir_fd or os.link not in os.supports_follow_symlinks:
        raise RuntimeError("safe no-follow hard links are unavailable")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    parent_fd = os.open(parent, flags)
    try:
        original = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        is_dir = stat.S_ISDIR(original.st_mode)
        for suffix in range(10000):
            candidate = f"{name}.backup.{timestamp}"
            if suffix:
                candidate += f".{suffix}"
            reserved = False
            moved = False
            stage_fd = None
            stage_name = None
            try:
                if is_dir:
                    # An empty directory is a safe reservation: rename cannot
                    # replace it after another process adds any user content.
                    os.mkdir(candidate, mode=0o700, dir_fd=parent_fd)
                    reserved = True
                    placeholder = os.stat(candidate, dir_fd=parent_fd,
                                          follow_symlinks=False)
                else:
                    os.link(name, candidate, src_dir_fd=parent_fd,
                            dst_dir_fd=parent_fd, follow_symlinks=False)
                    reserved = True

                current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
                claimed = os.stat(candidate, dir_fd=parent_fd,
                                  follow_symlinks=False)
                if _identity(current) != _identity(original):
                    raise RuntimeError("source changed during backup claim")
                if not is_dir and _identity(claimed) != _identity(original):
                    raise RuntimeError("backup claim does not match source")
                if is_dir and _identity(claimed) != _identity(placeholder):
                    raise RuntimeError("backup reservation was replaced")

                if is_dir:
                    os.rename(name, candidate, src_dir_fd=parent_fd,
                              dst_dir_fd=parent_fd)
                    moved = True
                else:
                    # Unlinking by the original name after the identity check
                    # can erase a concurrent replacement. Move the source
                    # into our private stage first; after verifying the moved
                    # inode, unlink only that pinned staged entry.
                    stage_name = f".{name}.safe-stage-{secrets.token_hex(16)}"
                    os.mkdir(stage_name, mode=0o700, dir_fd=parent_fd)
                    stage_fd = os.open(stage_name, flags, dir_fd=parent_fd)
                    os.rename(name, "source", src_dir_fd=parent_fd,
                              dst_dir_fd=stage_fd)
                    moved = True
                    staged = os.stat("source", dir_fd=stage_fd,
                                     follow_symlinks=False)
                    if _identity(staged) != _identity(original):
                        raise RuntimeError(
                            "concurrent source replacement moved to private stage: "
                            + os.path.join(parent, stage_name)
                        )
                    os.unlink("source", dir_fd=stage_fd)
                final = os.stat(candidate, dir_fd=parent_fd,
                                follow_symlinks=False)
                if _identity(final) != _identity(original):
                    raise RuntimeError("backup identity changed during move")
                return os.path.join(parent, candidate)
            except FileExistsError:
                # The candidate was claimed by another process. Try suffix +1
                # without ever renaming over that new user's entry.
                if not reserved:
                    continue
                raise
            finally:
                if stage_fd is not None:
                    os.close(stage_fd)
                    try:
                        # Nonempty stage after a race is evidence, not rubbish:
                        # retain it for manual recovery instead of deleting it.
                        os.rmdir(stage_name, dir_fd=parent_fd)
                    except OSError:
                        pass
                if reserved and not moved:
                    try:
                        # Only unlink a file/symlink if our exact claim remains.
                        current = os.stat(candidate, dir_fd=parent_fd,
                                          follow_symlinks=False)
                        if is_dir and _identity(current) == _identity(placeholder):
                            os.rmdir(candidate, dir_fd=parent_fd)
                        elif not is_dir and _identity(current) == _identity(original):
                            os.unlink(candidate, dir_fd=parent_fd)
                    except (FileNotFoundError, OSError):
                        pass
        raise RuntimeError("exhausted backup name suffixes")
    finally:
        os.close(parent_fd)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: safe-link-backup.py TARGET TIMESTAMP")
    try:
        print(backup(sys.argv[1], sys.argv[2]))
    except (OSError, RuntimeError, ValueError) as exc:
        raise SystemExit("❌ [Hard Block] backup failed: " + str(exc))
