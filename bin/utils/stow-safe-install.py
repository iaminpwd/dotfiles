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
def _parent(root_fd, parts, create=False, home=None):
    """Hold parents by inode; verify ancestry around each directory mutation.

    A pinned dirfd can point to a directory renamed outside HOME. A missing
    child requires mkdir(dir_fd=...), which is itself a filesystem write.
    Validate the current parent before mkdir and the newly opened child
    afterwards, before the caller can create a managed leaf within it.
    As with symlinkat, POSIX cannot make inode-ancestry validation atomic with
    a concurrent rename inside the syscall; detect the remaining window.
    """
    if create and home is None:
        raise ValueError("secure parent creation requires the original HOME path")
    fd = os.dup(root_fd)
    walked = []
    try:
        for component in parts:
            created = False
            try:
                child = os.open(component, DIR_FLAGS, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    yield None
                    return
                _verify_home_root(root_fd, home)
                _verify_parent(root_fd, walked, fd)
                try:
                    os.mkdir(component, mode=0o755, dir_fd=fd)
                except FileExistsError:
                    pass
                child = os.open(component, DIR_FLAGS, dir_fd=fd)
                created = True
            os.close(fd)
            fd = child
            walked.append(component)
            if created:
                _verify_parent(root_fd, walked, fd)
                _verify_home_root(root_fd, home)
        yield fd
    finally:
        os.close(fd)


def _filtered_files(stow_dir, package, home):
    source_dir = os.path.join(stow_dir, package)
    source_prefix = source_dir + os.sep
    dirs = []
    files = []
    # os.walk silently skips unreadable directories unless onerror is set.
    # A partial inventory could incorrectly report "no drift" or omit files.
    def fail_on_walk_error(error):
        raise error

    for current, names, leaves in os.walk(
        source_dir, followlinks=False, onerror=fail_on_walk_error
    ):
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
        observed = os.lstat(absolute)
        if not stat.S_ISREG(observed.st_mode):
            raise RuntimeError("Stow source is no longer a regular file: " + absolute)
        entries.append((parts, absolute, (observed.st_dev, observed.st_ino)))
    return entries


def _verify_source_anchors(stow_dir, stow_fd, package, package_fd):
    """Verify live paths still identify the pinned source root and package.

    Open source dirfds can continue reading a directory after it is renamed;
    the installed HOME symlink instead resolves through the live source path.
    """
    try:
        root_now = os.stat(stow_dir, follow_symlinks=False)
        package_now = os.stat(package, dir_fd=stow_fd, follow_symlinks=False)
    except OSError as exc:
        if exc.errno in (errno.ENOENT, errno.ENOTDIR, errno.ELOOP):
            raise RuntimeError(
                "Stow source root moved or package directory replaced during install"
            ) from exc
        raise
    root_was, package_was = os.fstat(stow_fd), os.fstat(package_fd)
    if (not stat.S_ISDIR(root_now.st_mode)
            or (root_now.st_dev, root_now.st_ino)
            != (root_was.st_dev, root_was.st_ino)):
        raise RuntimeError("Stow source root moved or replaced during install")
    if (not stat.S_ISDIR(package_now.st_mode)
            or (package_now.st_dev, package_now.st_ino)
            != (package_was.st_dev, package_was.st_ino)):
        raise RuntimeError("Stow package directory moved or replaced during install")


def _verify_source(stow_fd, package, parts, expected):
    """Reject source symlink/parent replacement since filtered inventory.

    Resolve components from a pinned Stow root via O_NOFOLLOW directory FDs
    and inspect the leaf without following symlinks. Never use realpath() on a
    mutable source leaf to construct the installed symlink text.
    """
    try:
        with _parent(stow_fd, [package, *parts[:-1]]) as source_parent:
            if source_parent is None:
                raise RuntimeError("Stow source parent disappeared")
            _verify_parent(stow_fd, [package, *parts[:-1]], source_parent)
            entry = os.stat(parts[-1], dir_fd=source_parent,
                            follow_symlinks=False)
            if not stat.S_ISREG(entry.st_mode):
                raise RuntimeError("Stow source changed type after inventory")
            if (entry.st_dev, entry.st_ino) != expected:
                raise RuntimeError("Stow source inode changed after inventory")
    except OSError as exc:
        if exc.errno in (errno.ENOENT, errno.ENOTDIR, errno.ELOOP):
            raise RuntimeError("Stow source path changed after inventory") from exc
        raise


def _owned(entry_fd, name, source, parent_path, allow_absolute=False):
    entry = os.stat(name, dir_fd=entry_fd, follow_symlinks=False)
    if not stat.S_ISLNK(entry.st_mode):
        return False
    raw = os.readlink(name, dir_fd=entry_fd)
    if os.path.isabs(raw) and not allow_absolute:
        return False
    # Check the link text without following HOME parents. Source may itself
    # contain symlinks from a separate trusted repository checkout.
    return os.path.realpath(os.path.join(parent_path, raw)) == os.path.realpath(source)


def check_drift(stow_dir, package, home):
    """Read-only Stow package drift check. Print 1 if any managed link is missing.

    Ansible previously reimplemented the GNU Stow inventory and canonical
    symlink comparison in an embedded Bash program. Reuse the installer's
    filter, source validation and no-follow HOME traversal in one place.
    Existing absolute links to the same source count as clean for reporting,
    as they did in the former Ansible check; the installer itself still
    deliberately refuses to claim absolute links when applying changes.
    """
    _require_secure_dirfds()
    stow_dir = os.path.abspath(stow_dir)
    home = os.path.abspath(home)
    if os.path.basename(package) != package or package in ("", ".", ".."):
        raise ValueError("invalid package name")

    stow_fd = os.open(stow_dir, DIR_FLAGS)
    try:
        package_fd = os.open(package, DIR_FLAGS, dir_fd=stow_fd)
    except BaseException:
        os.close(stow_fd)
        raise
    try:
        _verify_source_anchors(stow_dir, stow_fd, package, package_fd)
        entries = _filtered_files(stow_dir, package, home)
        _verify_source_anchors(stow_dir, stow_fd, package, package_fd)
        root_fd = os.open(home, DIR_FLAGS)
    except BaseException:
        os.close(package_fd)
        os.close(stow_fd)
        raise

    try:
        _verify_home_root(root_fd, home)
        drift = False
        for parts, source, expected in entries:
            _verify_source_anchors(stow_dir, stow_fd, package, package_fd)
            _verify_source(stow_fd, package, parts, expected)
            parent_path = os.path.join(home, *parts[:-1])
            with _parent(root_fd, parts[:-1]) as parent_fd:
                if parent_fd is None:
                    drift = True
                    break
                _verify_parent(root_fd, parts[:-1], parent_fd)
                try:
                    owned = _owned(
                        parent_fd, parts[-1], source, parent_path,
                        allow_absolute=True,
                    )
                except FileNotFoundError:
                    owned = False
                # Reject detached/replaced parents even if the observed
                # symlink content happened to match the managed source.
                _verify_parent(root_fd, parts[:-1], parent_fd)
                _verify_home_root(root_fd, home)
                if not owned:
                    drift = True
                    break
        _verify_source_anchors(stow_dir, stow_fd, package, package_fd)
        _verify_home_root(root_fd, home)
        print("1" if drift else "0")
    finally:
        os.close(root_fd)
        os.close(package_fd)
        os.close(stow_fd)


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
    canonical_stow = os.path.realpath(stow_dir)
    if os.path.basename(package) != package or package in ("", ".", ".."):
        raise ValueError("invalid package name")
    # Pin source root/package before the pathname-based GNU Stow inventory.
    stow_fd = os.open(stow_dir, DIR_FLAGS)
    try:
        package_fd = os.open(package, DIR_FLAGS, dir_fd=stow_fd)
    except BaseException:
        os.close(stow_fd)
        raise
    try:
        _verify_source_anchors(stow_dir, stow_fd, package, package_fd)
        entries = _filtered_files(stow_dir, package, home)
        _verify_source_anchors(stow_dir, stow_fd, package, package_fd)
        root_fd = os.open(home, DIR_FLAGS)
    except BaseException:
        os.close(package_fd)
        os.close(stow_fd)
        raise
    try:
        _verify_home_root(root_fd, home)
        # Preflight all existing entries before creating any new symlink.
        for parts, source, expected in entries:
            _verify_source_anchors(stow_dir, stow_fd, package, package_fd)
            _verify_source(stow_fd, package, parts, expected)
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

        for parts, source, expected in entries:
            _verify_source_anchors(stow_dir, stow_fd, package, package_fd)
            _verify_source(stow_fd, package, parts, expected)
            parent_path = os.path.join(home, *parts[:-1])
            with _parent(root_fd, parts[:-1], create=True, home=home) as parent_fd:
                # A pinned directory FD remains writable even after the inode
                # is renamed OUTSIDE HOME. Re-check its ancestry immediately
                # before every mutation as well as after. This narrows, but
                # cannot eliminate, a hostile rename during symlinkat itself.
                _verify_home_root(root_fd, home)
                _verify_parent(root_fd, parts[:-1], parent_fd)
                _verify_source_anchors(stow_dir, stow_fd, package, package_fd)
                _verify_source(stow_fd, package, parts, expected)
                canonical_parent = os.path.join(canonical_home, *parts[:-1])
                # Use the lexical path underneath the canonical repository
                # root. A newly introduced source symlink must not redirect
                # the generated link text directly to an unrelated file.
                canonical_source = os.path.join(canonical_stow, package, *parts)
                relative = os.path.relpath(canonical_source, canonical_parent)
                try:
                    os.symlink(relative, parts[-1], dir_fd=parent_fd)
                except FileExistsError:
                    if not _owned(parent_fd, parts[-1], source, parent_path):
                        raise RuntimeError("concurrent HOME entry blocks safe Stow install: "
                                           + os.path.join(parent_path, parts[-1]))
                _verify_source_anchors(stow_dir, stow_fd, package, package_fd)
                _verify_source(stow_fd, package, parts, expected)
                # Never automatically unlink here on a move: unlink(dir_fd)
                # has no inode compare-and-delete primitive, so concurrent
                # user replacement could itself be destroyed by cleanup.
                _verify_parent(root_fd, parts[:-1], parent_fd)
                _verify_home_root(root_fd, home)
        _verify_source_anchors(stow_dir, stow_fd, package, package_fd)
        _verify_home_root(root_fd, home)
    finally:
        os.close(package_fd)
        os.close(stow_fd)
        os.close(root_fd)


def check_package_conflicts(stow_dir, home, packages):
    """Read-only preflight: two packages must never claim the same HOME path."""
    owners = {}
    for package in packages:
        if os.path.basename(package) != package or package in ("", ".", ".."):
            raise ValueError("invalid Stow package name")
        # Reuse the same GNU Stow ignore matcher as backup and safe install.
        for parts, _, _ in _filtered_files(stow_dir, package, home):
            key = tuple(parts)
            for prior, owner in owners.items():
                if key == prior or key[:len(prior)] == prior or prior[:len(key)] == key:
                    raise RuntimeError(
                        "Stow package conflict: " + package + "/" + "/".join(parts)
                        + " overlaps " + owner + "/" + "/".join(prior)
                    )
            owners[key] = package


if __name__ == "__main__":
    try:
        if len(sys.argv) == 5 and sys.argv[1] == "--check-drift":
            check_drift(*sys.argv[2:])
        elif len(sys.argv) >= 5 and sys.argv[1] == "--check-packages":
            check_package_conflicts(sys.argv[2], sys.argv[3], sys.argv[4:])
        elif len(sys.argv) == 4:
            install(*sys.argv[1:])
        else:
            raise ValueError(
                "usage: stow-safe-install.py STOW_DIR PACKAGE HOME "
                "| --check-drift STOW_DIR PACKAGE HOME "
                "| --check-packages STOW_DIR HOME PACKAGE..."
            )
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as exc:
        raise SystemExit("❌ [Hard Block] 안전한 Stow 링크 설치 실패: " + str(exc))
