#!/usr/bin/env bash
# 실제 bootstrap_mise_config 함수를 격리된 HOME/저장소로 실행한다.
# mise 버전 정본을 읽기 위해 위험한 초기 GNU Stow 경로 쓰기가 필요하지
# 않은지, 충돌 백업과 두 번째 실행이 안전한지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

FN="$TMP/bootstrap-function.sh"
awk '
  /^bootstrap_mise_config\(\) \{/ { inside=1 }
  inside { print }
  inside && /^}/ { exit }
' "$ROOT/bootstrap.sh" >"$FN"
grep -q '^bootstrap_mise_config()' "$FN"
# shellcheck source=/dev/null
source "$FN"

if grep -Eq 'stow[[:space:]]+-t[[:space:]]|stow[[:space:]]+-R[[:space:]]' "$ROOT/bootstrap.sh"; then
  echo 'FAIL: 초기 bootstrap에서 파일 경로 기반 GNU Stow 쓰기가 재도입됐습니다.' >&2
  exit 1
fi

CASE="$TMP/working copy"
SCRIPT_DIR="$CASE/dotfiles"
mkdir -p "$SCRIPT_DIR/stow/mise/.config/mise" "$SCRIPT_DIR/bin/utils" \
  "$CASE/home/.local/bin" "$TMP/bin"
cp "$ROOT/stow/mise/.config/mise/config.toml" \
  "$SCRIPT_DIR/stow/mise/.config/mise/config.toml"
for script in stow-backup.sh stow-safe-backup.py stow-safe-install.py stow-filter-inventory.pl; do
  cp "$ROOT/bin/utils/$script" "$SCRIPT_DIR/bin/utils/$script"
done
HOME="$CASE/home"
export HOME
MISE_BOOTSTRAP_CALLS="$TMP/mise-calls"
MISE_BOOTSTRAP_INSTALLED="$TMP/mise-installed"
export MISE_BOOTSTRAP_CALLS MISE_BOOTSTRAP_INSTALLED

# 실제 mise가 override 파일을 글로벌 설정으로 선택하는지 확인한다.
# 기존 사용자 파일이 잘못된 TOML이어도 이 단계의 정본을 가리지 않아야 한다.
if command -v mise >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/mise"
  printf 'invalid - local user config\n' >"$HOME/.config/mise/config.toml"
  real_mise=$(command -v mise)
  status=0
  config_out=$(MISE_GLOBAL_CONFIG_FILE="$SCRIPT_DIR/stow/mise/.config/mise/config.toml" \
    "$real_mise" config ls 2>&1) || status=$?
  if [ "$status" -ne 0 ] || ! grep -qF "$SCRIPT_DIR/stow/mise/.config/mise/config.toml" <<<"$config_out"; then
    echo "FAIL: 실제 mise가 bootstrap 정본을 읽지 못했습니다: $config_out" >&2
    exit 1
  fi
  echo 'PASS: 실제 mise가 환경변수 지정 정본을 로드'
fi

cat >"$HOME/.local/bin/mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$MISE_GLOBAL_CONFIG_FILE" = "$MISE_BOOTSTRAP_SOURCE" ] || exit 71
[ -f "$MISE_GLOBAL_CONFIG_FILE" ] || exit 72
printf '%s\n' "$*" >>"$MISE_BOOTSTRAP_CALLS"
if [ "$*" = "install -y" ]; then
  : >"$MISE_BOOTSTRAP_INSTALLED"
fi
SH
chmod +x "$HOME/.local/bin/mise"
MISE_BOOTSTRAP_SOURCE="$SCRIPT_DIR/stow/mise/.config/mise/config.toml"
export MISE_BOOTSTRAP_SOURCE

# Python은 실제 설치 단계 이후에만 사용할 수 있다는 조건을 모사한다.
# Perl/dirfd 검증은 원본 구현을 그대로 실행한다.
if [ -x /usr/bin/python3 ]; then
  REAL_PYTHON=/usr/bin/python3
else
  REAL_PYTHON=$(command -v python3)
fi
cat >"$TMP/bin/python3" <<'SH'
#!/usr/bin/env bash
[ -f "$MISE_BOOTSTRAP_INSTALLED" ] || {
  echo "FAIL: mise install 이전에 Python이 필요합니다." >&2
  exit 73
}
exec "$MISE_BOOTSTRAP_REAL_PYTHON" "$@"
SH
chmod +x "$TMP/bin/python3"
MISE_BOOTSTRAP_REAL_PYTHON="$REAL_PYTHON"
export MISE_BOOTSTRAP_REAL_PYTHON
export PATH="$TMP/bin:$PATH"

# 사용자의 기존 글로벌 mise 설정은 백업되어야 한다.
mkdir -p "$HOME/.config/mise"
printf 'user-local-config\n' >"$HOME/.config/mise/config.toml"
bootstrap_mise_config

target="$HOME/.config/mise/config.toml"
[ -L "$target" ]
[ "$(realpath "$target")" = "$(realpath "$MISE_BOOTSTRAP_SOURCE")" ]
backups=("$target".backup.*)
[ "${#backups[@]}" -eq 1 ] && [ "$(cat "${backups[0]}")" = user-local-config ]
mapfile -t mise_calls <"$MISE_BOOTSTRAP_CALLS"
[ "${#mise_calls[@]}" -eq 2 ]
[ "${mise_calls[0]}" = "install -y uv" ]
[ "${mise_calls[1]}" = "install -y" ]
echo 'PASS: 버전 정본에서 uv/도구 설치 후 기존 사용자 config 백업·안전 링크'

# 링크 자체를 다시 설치해도 기존 파일을 추가 백업하지 않아야 한다.
bootstrap_mise_config
[ -L "$target" ]
backups=("$target".backup.*)
[ "${#backups[@]}" -eq 1 ]
echo 'PASS: 초기 mise 구성 재실행 멱등성'

# 외부 사용자 디렉터리 심볼릭 링크는 강제로 인수하지 않는다.
FOREIGN="$TMP/foreign"
mkdir -p "$FOREIGN"
printf 'foreign user data\n' >"$FOREIGN/keep.txt"
mv "$HOME/.config" "$HOME/.config-original"
ln -s "$FOREIGN" "$HOME/.config"
status=0
bootstrap_mise_config >"$TMP/foreign.log" 2>&1 || status=$?
if [ "$status" -eq 0 ] || [ ! -L "$HOME/.config" ] ||
  [ "$(cat "$FOREIGN/keep.txt")" != "foreign user data" ] ||
  ! grep -q 'Hard Block' "$TMP/foreign.log"; then
  cat "$TMP/foreign.log"
  echo 'FAIL: 외부 디렉터리 심볼릭 링크를 안전하게 차단하지 못했습니다.' >&2
  exit 1
fi
echo 'PASS: 외부 설정 디렉터리는 보존하고 설치를 차단'
