#!/usr/bin/env python3
"""Apply GNU Stow's filtered file inventory without path-based HOME writes.

GNU Stow -S uses pathname-based symlink() and mkdir() calls. A process that
replaces a HOME parent with a symlink between Stow's checks and its final
syscall can redirect those writes into an unrelated external directory.
Use the same GNU Stow Perl ignore matcher, but install leaf links through
O_NOFOLLOW parent dirfds. Never remove or replace an existing user entry.
"""
import errno
import os
import stat
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path


DIR_FLAGS = (
    os.O_RDONLY
    | getattr(os, "O_DIRECTORY", 0)
    | getattr(os, "O_NOFOLLOW", 0)
)
# Test fixtures temporarily intercept symlink() for deterministic TOCTOU
# injection. Platform capability must be checked against the real builtin
# recorded at import time, not the transient test intercept.
SECURE_SYMLINK_SUPPORTED = os.symlink in os.supports_dir_fd
SECURE_MKDIR_SUPPORTED = os.mkdir in os.supports_dir_fd


def _require_secure_dirfds():
    if not hasattr(os, "O_DIRECTORY") or not hasattr(os, "O_NOFOLLOW"):
        raise RuntimeError("secure no-follow directory opens unavailable")
    if not SECURE_SYMLINK_SUPPORTED:
        raise RuntimeError("secure directory-descriptor symlink unavailable")
    if not SECURE_MKDIR_SUPPORTED:
        raise RuntimeError("secure directory-descriptor mkdir unavailable")
    for operation in (os.open, os.stat, os.readlink):
        if operation not in os.supports_dir_fd:
            raise RuntimeError("secure directory-descriptor operation unavailable")
    if os.stat not in os.supports_follow_symlinks:
        raise RuntimeError("secure no-follow stat unavailable")


@contextmanager
def _parent(root_fd, parts, create=False):
    """Hold each opened parent by inode, never traverse a symlink."""
    fd = os.dup(root_fd)
    try:
        for component in parts:
            try:
                child = os.open(component, DIR_FLAGS, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    yield None
                    return
                try:
                    os.mkdir(component, mode=0o755, dir_fd=fd)
                except FileExistsError:
                    pass
                child = os.open(component, DIR_FLAGS, dir_fd=fd)
            os.close(fd)
            fd = child
        yield fd
    finally:
        os.close(fd)


def _filtered_files(stow_dir, package, home):
    source_dir = os.path.join(stow_dir, package)
    source_prefix = source_dir + os.sep
    dirs = []
    files = []
    for current, names, leaves in os.walk(source_dir, followlinks=False):
        for name in names:
            path = os.path.join(current, name)
            if stat.S_ISLNK(os.lstat(path).st_mode):
                raise RuntimeError("source contains an unsupported directory symlink")
            dirs.append(path)
        for name in leaves:
            path = os.path.join(current, name)
            if not stat.S_ISREG(os.lstat(path).st_mode):
                raise RuntimeError("source contains a nonregular file")
            files.append(path)
    with tempfile.TemporaryDirectory(prefix="stow-safe-inventory-") as temp:
        paths = [os.path.join(temp, n) for n in (
            "dirs", "files", "filtered-dirs", "filtered-files"
        )]
        for path, entries in zip(paths[:2], (dirs, files)):
            with open(path, "wb") as out:
                for entry in entries:
                    out.write(os.fsencode(entry) + b"\0")
        filter_script = os.path.join(
            os.path.dirname(__file__), "stow-filter-inventory.pl"
        )
        environment = dict(os.environ, HOME=home)
        subprocess.run(
            ["perl", filter_script, stow_dir, package, home, source_prefix,
             *paths],
            check=True, env=environment,
        )
        with open(paths[3], "rb") as source:
            filtered = source.read().split(b"\0")
    entries = []
    for item in filtered:
        if not item:
            continue
        absolute = os.fsdecode(item)
        if absolute not in files or not absolute.startswith(source_prefix):
            raise RuntimeError("invalid GNU Stow filtered source inventory")
        relative = absolute[len(source_prefix):]
        parts = relative.split(os.sep)
        if any(part in ("", ".", "..") for part in parts):
            raise RuntimeError("invalid Stow source path")
        entries.append((parts, absolute))
    return entries


def _owned(entry_fd, name, source, parent_path):
    entry = os.stat(name, dir_fd=entry_fd, follow_symlinks=False)
    if not stat.S_ISLNK(entry.st_mode):
        return False
    raw = os.readlink(name, dir_fd=entry_fd)
    if os.path.isabs(raw):
        return False
    # Check the link text without following HOME parents. Source may itself
    # contain symlinks from a separate trusted repository checkout.
    return os.path.realpath(os.path.join(parent_path, raw)) == os.path.realpath(source)


def _verify_parent(root_fd, parts, pinned_fd):
    try:
        with _parent(root_fd, parts, create=False) as current:
            if current is None:
                raise RuntimeError("HOME parent replaced during safe Stow apply")
            a, b = os.fstat(pinned_fd), os.fstat(current)
            if (a.st_dev, a.st_ino) != (b.st_dev, b.st_ino):
                raise RuntimeError("HOME parent replaced during safe Stow apply")
    except OSError as exc:
        if exc.errno in (errno.ENOENT, errno.ENOTDIR, errno.ELOOP):
            raise RuntimeError("HOME parent replaced during safe Stow apply") from exc
        raise


def _verify_home_root(root_fd, home):
    """Detect a renamed/replaced HOME inode before and after leaf installation."""
    try:
        observed = os.stat(home, follow_symlinks=False)
    except OSError as exc:
        if exc.errno in (errno.ENOENT, errno.ENOTDIR, errno.ELOOP):
            raise RuntimeError("HOME root moved or replaced during safe Stow apply") from exc
        raise
    original = os.fstat(root_fd)
    if (original.st_dev, original.st_ino) != (observed.st_dev, observed.st_ino):
        raise RuntimeError("HOME root moved or replaced during safe Stow apply")


def install(stow_dir, package, home):
    _require_secure_dirfds()
    stow_dir = os.path.abspath(stow_dir)
    home = os.path.abspath(home)
    # macOS can expose the same temp directory as /var/... and /private/var/...
    # Compute link *text* from canonical roots while all filesystem writes
    # still use the original no-follow HOME dirfd.
    canonical_home = os.path.realpath(home)
    if os.path.basename(package) != package or package in ("", ".", ".."):
        raise ValueError("invalid package name")
    entries = _filtered_files(stow_dir, package, home)
    root_fd = os.open(home, DIR_FLAGS)
    try:
        _verify_home_root(root_fd, home)
        # Preflight all existing entries before creating any new symlink.
        for parts, source in entries:
            parent_path = os.path.join(home, *parts[:-1])
            with _parent(root_fd, parts[:-1]) as parent_fd:
                if parent_fd is None:
                    continue
                try:
                    owned = _owned(parent_fd, parts[-1], source, parent_path)
                except FileNotFoundError:
                    continue
                if not owned:
                    raise RuntimeError("foreign HOME entry blocks safe Stow install: "
                                       + os.path.join(parent_path, parts[-1]))

        for parts, source in entries:
            parent_path = os.path.join(home, *parts[:-1])
            with _parent(root_fd, parts[:-1], create=True) as parent_fd:
                # A pinned directory FD remains writable even after the inode
                # is renamed OUTSIDE HOME. Re-check its ancestry immediately
                # before every mutation as well as after. This narrows, but
                # cannot eliminate, a hostile rename during symlinkat itself.
                _verify_home_root(root_fd, home)
                _verify_parent(root_fd, parts[:-1], parent_fd)
                canonical_parent = os.path.join(canonical_home, *parts[:-1])
                relative = os.path.relpath(
                    os.path.realpath(source), canonical_parent
                )
                try:
                    os.symlink(relative, parts[-1], dir_fd=parent_fd)
                except FileExistsError:
                    if not _owned(parent_fd, parts[-1], source, parent_path):
                        raise RuntimeError("concurrent HOME entry blocks safe Stow install: "
                                           + os.path.join(parent_path, parts[-1]))
                # Never automatically unlink here on a move: unlink(dir_fd)
                # has no inode compare-and-delete primitive, so concurrent
                # user replacement could itself be destroyed by cleanup.
                _verify_parent(root_fd, parts[:-1], parent_fd)
                _verify_home_root(root_fd, home)
        _verify_home_root(root_fd, home)
    finally:
        os.close(root_fd)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: stow-safe-install.py STOW_DIR PACKAGE HOME")
    try:
        install(*sys.argv[1:])
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as exc:
        raise SystemExit("❌ [Hard Block] 안전한 Stow 링크 설치 실패: " + str(exc))
