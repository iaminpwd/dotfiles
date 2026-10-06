#!/usr/bin/env bash
# Fresh Linux 설치 직후 docker 그룹 반영에 새 로그인 세션이 필요한 상태를 안내하는지 검증한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

DOCKER_ROLE="$ROOT/ansible/roles/docker/tasks/main.yml"
BOOTSTRAP="$ROOT/bootstrap.sh"

# 이 저장소가 실제로 계정 DB의 docker 그룹을 변경하는지 먼저 고정한다.
grep -Fq 'groups: docker' "$DOCKER_ROLE"
grep -Fq 'append: true' "$DOCKER_ROLE"

python3 - "$BOOTSTRAP" "$TMP/function.sh" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text()
match = re.search(
    r'^warn_docker_group_refresh\(\) \{\n.*?^\}\n',
    source,
    re.M | re.S,
)
if not match:
    raise SystemExit(
        "FAIL: bootstrap.sh에 fresh-install docker 그룹 세션 갱신 감지 함수가 없습니다."
    )
Path(sys.argv[2]).write_text(match.group(0))
PY

# shellcheck disable=SC1090
source "$TMP/function.sh"

mkdir -p "$TMP/bin"
cat >"$TMP/bin/uname" <<'STUB'
#!/bin/sh
if [ "${1:-}" = "-s" ]; then
  printf '%s\n' "${FAKE_UNAME:-Linux}"
else
  printf '%s\n' "${FAKE_UNAME:-Linux}"
fi
STUB

cat >"$TMP/bin/id" <<'STUB'
#!/bin/sh
case "$*" in
-u)
  printf '%s\n' "${FAKE_UID:-1000}"
  ;;
-un)
  printf '%s\n' "${FAKE_USER:-tester}"
  ;;
-nG)
  printf '%s\n' "${FAKE_CURRENT_GROUPS:-tester sudo}"
  ;;
"-nG tester")
  printf '%s\n' "${FAKE_ACCOUNT_GROUPS:-tester sudo docker}"
  ;;
*)
  echo "unexpected id args: $*" >&2
  exit 99
  ;;
esac
STUB
chmod +x "$TMP/bin/uname" "$TMP/bin/id"

# 계정 DB에는 docker가 생겼지만 현재 프로세스 group vector에는 아직 없는 fresh-install 상태.
out=$(PATH="$TMP/bin:/usr/bin:/bin"   FAKE_UID=1000 FAKE_USER=tester   FAKE_CURRENT_GROUPS='tester sudo'   FAKE_ACCOUNT_GROUPS='tester sudo docker'   warn_docker_group_refresh)

grep -q 'Docker' <<<"$out"
if ! grep -Eq '로그아웃|다시 로그인|newgrp docker' <<<"$out"; then
  echo "FAIL: stale docker 그룹 상태를 감지했지만 새 로그인 세션 방법을 안내하지 않습니다."
  printf '%s\n' "$out"
  exit 1
fi

# 이미 현재 세션에도 docker 그룹이 활성화된 경우 경고하면 안 된다.
out=$(PATH="$TMP/bin:/usr/bin:/bin"   FAKE_UID=1000 FAKE_USER=tester   FAKE_CURRENT_GROUPS='tester sudo docker'   FAKE_ACCOUNT_GROUPS='tester sudo docker'   warn_docker_group_refresh)
[ -z "$out" ] || {
  echo "FAIL: docker 그룹이 이미 활성화됐는데 불필요한 재로그인 경고가 출력됐습니다: $out"
  exit 1
}

# root는 docker socket 접근에 supplementary docker 그룹 갱신이 필요 없다.
out=$(PATH="$TMP/bin:/usr/bin:/bin"   FAKE_UID=0 FAKE_USER=tester   FAKE_CURRENT_GROUPS='root'   FAKE_ACCOUNT_GROUPS='tester sudo docker'   warn_docker_group_refresh)
[ -z "$out" ] || {
  echo "FAIL: root 실행에도 docker 그룹 세션 경고를 출력했습니다: $out"
  exit 1
}

echo 'PASS: fresh Linux Docker 그룹 세션 갱신 필요 상태를 정확히 안내함'
