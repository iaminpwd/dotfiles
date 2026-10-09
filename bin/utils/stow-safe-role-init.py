#!/usr/bin/env python3
"""Safely prepare Mise's HOME directory and retire an owned legacy link.

Do not separate an Ansible stat/assert from later path-based mkdir/unlink:
another writer may replace an already checked HOME entry between tasks.
Reuse the Stow installer's O_NOFOLLOW dirfds and inode ancestry checks.
Never traverse or mutate a foreign config symlink. For legacy cleanup,
move the link into a private stage and verify the *moved* inode before
unlinking it; restore/preserve any concurrent user replacement.
"""
import importlib.util
import os
import secrets
import stat
import sys

spec = importlib.util.spec_from_file_location(
    "stow_safe_install",
    os.path.join(os.path.dirname(__file__), "stow-safe-install.py"),
)
secure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(secure)


def _entry(fd, name):
    try:
        return os.stat(name, dir_fd=fd, follow_symlinks=False)
    except FileNotFoundError:
        return None


def _expected_symlink(fd, name, parent, expected):
    raw = os.readlink(name, dir_fd=fd)
    actual = os.path.realpath(os.path.join(parent, raw))
    return actual == os.path.realpath(expected)


def _foreign_config(path):
    raise RuntimeError(
        "외부 Mise 설정 디렉토리 링크 사전 차단: " + path
    )


def _ensure_mise(home, repository, fd, check):
    config = ".config"
    config_path = os.path.join(home, config)
    config_expected = os.path.join(repository, "stow/mise/.config")
    mise_expected = os.path.join(config_expected, "mise")
    current = _entry(fd, config)

    # Historical Stow tree-folding: keep the *owned* directory symlink, but
    # never mkdir through it. Foreign parents must be rejected before writes.
    if current is not None and stat.S_ISLNK(current.st_mode):
        if not _expected_symlink(fd, config, home, config_expected):
            _foreign_config(config_path)
        nested_path = os.path.join(config_path, "mise")
        try:
            nested = os.lstat(nested_path)
        except FileNotFoundError:
            raise RuntimeError(
                "기존 Stow 관리 .config 내부 mise 디렉토리가 없습니다: "
                + nested_path
            )
        if stat.S_ISLNK(nested.st_mode):
            if os.path.realpath(nested_path) != os.path.realpath(mise_expected):
                _foreign_config(nested_path)
        elif not stat.S_ISDIR(nested.st_mode):
            raise RuntimeError("Mise 설정 경로가 디렉토리가 아닙니다: " + nested_path)
        secure._verify_home_root(fd, home)
        print("UNCHANGED: existing managed .config/mise directory")
        return

    if current is not None and not stat.S_ISDIR(current.st_mode):
        raise RuntimeError("Mise 설정 경로가 디렉토리가 아닙니다: " + config_path)

    if current is None and check:
        print("CHANGED: would create .config/mise")
        return

    with secure._parent(
        fd, [config], create=not check, home=home if not check else None
    ) as config_fd:
        if config_fd is None:
            print("CHANGED: would create .config/mise")
            return
        nested = _entry(config_fd, "mise")
        if nested is not None and stat.S_ISLNK(nested.st_mode):
            if not _expected_symlink(
                config_fd, "mise", config_path, mise_expected
            ):
                _foreign_config(os.path.join(config_path, "mise"))
            if not os.path.isdir(os.path.join(config_path, "mise")):
                raise RuntimeError("Stow 관리 mise 링크의 대상 디렉토리가 없습니다")
            secure._verify_parent(fd, [config], config_fd)
            print("UNCHANGED: existing managed mise directory symlink")
            return
        if nested is not None:
            if not stat.S_ISDIR(nested.st_mode):
                raise RuntimeError("Mise 설정 경로가 디렉토리가 아닙니다")
            secure._verify_parent(fd, [config], config_fd)
            print("UNCHANGED: .config/mise directory")
            return

    if check:
        print("CHANGED: would create .config/mise")
        return
    with secure._parent(
        fd, [config, "mise"], create=True, home=home
    ) as nested_fd:
        secure._verify_parent(fd, [config, "mise"], nested_fd)
        secure._verify_home_root(fd, home)
    print("CHANGED: created .config/mise directory")


def _identity(obj):
    return (obj.st_dev, obj.st_ino, obj.st_mode)


def _retire_legacy(home, repository, fd, check):
    name = ".mise.toml"
    expected = os.path.join(repository, "mise/.mise.toml")
    current = _entry(fd, name)
    if current is None or not stat.S_ISLNK(current.st_mode):
        print("UNCHANGED: no owned legacy Mise symlink")
        return
    if not _expected_symlink(fd, name, home, expected):
        print("UNCHANGED: foreign legacy Mise symlink preserved")
        return
    raw = os.readlink(name, dir_fd=fd)
    if check:
        print("CHANGED: would retire owned legacy Mise symlink")
        return

    if (os.link not in os.supports_dir_fd
            or os.link not in os.supports_follow_symlinks):
        raise RuntimeError("legacy cleanup requires no-follow linkat support")
    stage = f".mise.toml.stow-stage-{secrets.token_hex(16)}"
    secure._verify_home_root(fd, home)
    os.mkdir(stage, mode=0o700, dir_fd=fd)
    stage_fd = os.open(stage, secure.DIR_FLAGS, dir_fd=fd)
    keep_stage = False
    try:
        secure._verify_home_root(fd, home)
        # Recheck the same inode immediately before moving it into private
        # staging. The post-rename check catches a subsequent replacement.
        before_move = _entry(fd, name)
        if (before_move is None
                or _identity(before_move) != _identity(current)
                or os.readlink(name, dir_fd=fd) != raw):
            raise RuntimeError("legacy Mise source changed before staging")
        os.rename(name, "source", src_dir_fd=fd, dst_dir_fd=stage_fd)
        moved = _entry(stage_fd, "source")
        if (moved is None or _identity(moved) != _identity(current)
                or not stat.S_ISLNK(moved.st_mode)
                or os.readlink("source", dir_fd=stage_fd) != raw):
            # Never delete an unexpected user file after a concurrent swap.
            # linkat is no-clobber: a new user pathname cannot be overwritten.
            keep_stage = True
            try:
                os.link(
                    "source", name, src_dir_fd=stage_fd, dst_dir_fd=fd,
                    follow_symlinks=False,
                )
            except FileExistsError:
                raise RuntimeError(
                    "legacy Mise source replaced; user entry preserved in "
                    + os.path.join(home, stage, "source")
                )
            os.unlink("source", dir_fd=stage_fd)
            keep_stage = False
            raise RuntimeError("legacy Mise source replaced; restored user entry")
        secure._verify_home_root(fd, home)
        os.unlink("source", dir_fd=stage_fd)
    finally:
        os.close(stage_fd)
        if not keep_stage:
            os.rmdir(stage, dir_fd=fd)
    secure._verify_home_root(fd, home)
    print("CHANGED: retired owned legacy Mise symlink")


def run(action, home, repository, check):
    secure._require_secure_dirfds()
    home = os.path.abspath(home)
    repository = os.path.abspath(repository)
    fd = os.open(home, secure.DIR_FLAGS)
    try:
        secure._verify_home_root(fd, home)
        if action == "mise":
            _ensure_mise(home, repository, fd, check)
        elif action == "legacy":
            _retire_legacy(home, repository, fd, check)
        else:
            raise ValueError("unknown stow entry action")
        secure._verify_home_root(fd, home)
    finally:
        os.close(fd)


if __name__ == "__main__":
    if len(sys.argv) != 5 or sys.argv[4] not in ("--check", "--apply"):
        raise SystemExit(
            "usage: stow-safe-role-init.py mise|legacy HOME REPO_ROOT --check|--apply"
        )
    try:
        run(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "--check")
    except (OSError, RuntimeError, ValueError) as exc:
        raise SystemExit("❌ [Hard Block] 안전한 Stow 초기화 실패: " + str(exc))
