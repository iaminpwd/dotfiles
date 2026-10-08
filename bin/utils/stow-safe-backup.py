#!/usr/bin/env python3
"""Move a Stow conflict to a backup without traversing symlinked HOME parents.

All path components are opened relative to an O_NOFOLLOW directory descriptor.
This matters if another process swaps a checked directory for a foreign symlink
between the backup script's preflight and the eventual rename syscall.
"""
import os
import stat
import sys


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

        # Retain the existing timestamp + numeric suffix collision convention.
        base = f"{name}.backup.{timestamp}"
        suffix = 0
        while True:
            dest = base if suffix == 0 else f"{base}.{suffix}"
            try:
                os.stat(dest, dir_fd=fd, follow_symlinks=False)
            except FileNotFoundError:
                break
            suffix += 1

        # Source and destination are resolved inside the SAME opened parent.
        # Swapping HOME/.config for a foreign symlink cannot redirect this mv.
        os.rename(name, dest, src_dir_fd=fd, dst_dir_fd=fd)
    finally:
        os.close(fd)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: stow-safe-backup.py HOME TARGET TIMESTAMP")
    try:
        backup(*sys.argv[1:])
    except (OSError, ValueError, RuntimeError) as exc:
        raise SystemExit(f"❌ [Hard Block] 안전한 백업 이동 실패: {exc}")
