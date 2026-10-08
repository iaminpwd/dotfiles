#!/usr/bin/env bash
# Backup must leave GNU Stow-ignored user files in place, without guesswork.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
BACKUP="$ROOT/bin/utils/stow-backup.sh"
if ! command -v stow >/dev/null 2>&1; then
  if [ "${STOW_REQUIRE_REAL:-0}" = 1 ]; then
    echo 'FAIL: GNU Stow is required for ignore parity regression' >&2
    exit 1
  fi
  echo '[WARNING] SKIP: GNU Stow is not installed'
  exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Global ignore: user content excluded by Stow must never be backed up.
CASE="$TMP/global"
mkdir -p "$CASE/stow/demo" "$CASE/home"
printf 'managed skip\n' >"$CASE/stow/demo/.skip"
printf 'managed install\n' >"$CASE/stow/demo/.install"
printf 'user skip\n' >"$CASE/home/.skip"
printf 'user install\n' >"$CASE/home/.install"
printf '^\\.skip$\n' >"$CASE/home/.stow-global-ignore"
HOME="$CASE/home" bash "$BACKUP" demo "$CASE/stow" "$CASE/home"
BACKUPS=("$CASE/home"/.install.backup.*)
SKIP_BACKUPS=("$CASE/home"/.skip.backup.*)
if ! grep -qx 'user skip' "$CASE/home/.skip" ||
  [ -e "${SKIP_BACKUPS[0]}" ] ||
  [ ! -f "${BACKUPS[0]}" ] ||
  ! grep -qx 'user install' "${BACKUPS[0]}" ||
  [ -e "$CASE/home/.install" ]; then
  echo 'FAIL: global Stow ignore moved the user-owned ignored file'
  exit 1
fi
(
  cd "$CASE/stow"
  HOME="$CASE/home" stow -R --no-folding -t "$CASE/home" demo
)
if [ ! -L "$CASE/home/.install" ] ||
  ! grep -qx 'managed install' "$CASE/home/.install" ||
  ! grep -qx 'user skip' "$CASE/home/.skip" ||
  ! grep -qx 'user install' "${BACKUPS[0]}"; then
  echo 'FAIL: real GNU Stow and backup disagree on global ignore'
  exit 1
fi

# A local ignore file overrides the global ignore rules for this package.
# Also exercise ignored directories whose HOME path is an existing user file.
CASE="$TMP/local"
mkdir -p "$CASE/stow/demo/.excluded" "$CASE/home"
printf 'managed skip\n' >"$CASE/stow/demo/.skip"
printf 'managed nested\n' >"$CASE/stow/demo/.excluded/private"
printf 'managed install\n' >"$CASE/stow/demo/.install"
printf 'user skip\n' >"$CASE/home/.skip"
printf 'user excluded\n' >"$CASE/home/.excluded"
printf 'user install\n' >"$CASE/home/.install"
printf '^\\.skip$\n^\\.excluded$\n' >"$CASE/stow/demo/.stow-local-ignore"
printf '^\\.something-else$\n' >"$CASE/home/.stow-global-ignore"
STOW_FILTER_TRACE=1 HOME="$CASE/home" bash "$BACKUP" demo "$CASE/stow" "$CASE/home"
BACKUPS=("$CASE/home"/.install.backup.*)
SKIP_BACKUPS=("$CASE/home"/.skip.backup.*)
EXCLUDED_BACKUPS=("$CASE/home"/.excluded.backup.*)
if ! grep -qx 'user skip' "$CASE/home/.skip" ||
  ! grep -qx 'user excluded' "$CASE/home/.excluded" ||
  [ -e "${SKIP_BACKUPS[0]}" ] ||
  [ -e "${EXCLUDED_BACKUPS[0]}" ] ||
  ! grep -qx 'user install' "${BACKUPS[0]}"; then
  echo 'FAIL: local ignore or ignored directory altered user files'
  exit 1
fi
(
  cd "$CASE/stow"
  HOME="$CASE/home" stow -R --no-folding -t "$CASE/home" demo
)
if [ ! -L "$CASE/home/.install" ] ||
  ! grep -qx 'user skip' "$CASE/home/.skip" ||
  ! grep -qx 'user excluded' "$CASE/home/.excluded" ||
  ! grep -qx 'user install' "${BACKUPS[0]}"; then
  echo 'FAIL: real Stow and backup disagree on local ignore'
  exit 1
fi

# Invalid regex: fail closed before moving any user target.
CASE="$TMP/invalid"
mkdir -p "$CASE/stow/demo" "$CASE/home"
printf 'managed install\n' >"$CASE/stow/demo/.install"
printf 'user install\n' >"$CASE/home/.install"
printf '[\n' >"$CASE/home/.stow-global-ignore"
status=0
HOME="$CASE/home" bash "$BACKUP" demo "$CASE/stow" "$CASE/home" >"$CASE/result" 2>&1 || status=$?
BACKUPS=("$CASE/home"/.install.backup.*)
if [ "$status" -eq 0 ] ||
  ! grep -qF '[Hard Block]' "$CASE/result" ||
  ! grep -qx 'user install' "$CASE/home/.install" ||
  [ -e "${BACKUPS[0]}" ]; then
  cat "$CASE/result"
  echo 'FAIL: malformed Stow ignore rules did not block before backup'
  exit 1
fi
echo 'PASS: GNU Stow ignore parity (global, local, nested directory, invalid regex)'
