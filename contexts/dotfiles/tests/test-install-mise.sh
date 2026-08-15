#!/usr/bin/env bash
# test-install-mise.sh
#
# bin/utils/install-mise.sh 는 bootstrap.sh(로컬 셋업)와 ci.yml(verify job)이 공유하는
# mise 설치 진입점이다. 이 스크립트가 하는 일은 사실상 "공식 GPG 키로 설치 스크립트
# 서명을 검증한다" 하나이므로, 그 판정이 느슨해지면 검증 없이 임의 코드를 실행하는
# 경로가 된다 — 검증이 죽어도 설치는 성공하니 아무도 모른다.
#
# 실제 설치는 네트워크에 의존하므로 여기서 반복하지 않는다. 대신 네트워크 없이 확인
# 가능한 두 축을 고정한다: (1) 이미 설치돼 있으면 아무것도 하지 않는다(멱등),
# (2) 지문 판정이 "주 키가 정확히 1개이고 기대값"인가.
#
# (2)는 판정식을 이 파일에 복제하지 않는다. 복제하면 본체만 고쳤을 때 테스트가 그대로
# 통과해 회귀를 못 잡는다(test-finops.sh 가 실제로 그 상태였다). 스크립트에서 awk 식을
# 그대로 뽑아내 합성 키링에 태운다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-install-mise.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
INSTALLER="$REPO_ROOT/bin/utils/install-mise.sh"

PASS_COUNT=0
FAIL_COUNT=0

report() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" -eq 0 ]; then
    echo "  PASS  $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL  $name"
    [ -n "$detail" ] && echo "        $detail"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "=== install-mise.sh 공급망 판정 회귀 테스트 ==="

# 1. 멱등: 이미 mise 가 있으면 네트워크를 타지 않고 즉시 0.
IDEM_HOME="$TMP/idem"
mkdir -p "$IDEM_HOME/.local/bin"
printf '#!/bin/sh\nexit 0\n' >"$IDEM_HOME/.local/bin/mise"
chmod +x "$IDEM_HOME/.local/bin/mise"

status=0
out=$(HOME="$IDEM_HOME" bash "$INSTALLER" 2>&1) || status=$?
if [ "$status" -eq 0 ] && [ -z "$out" ]; then
  report "already-installed (재실행 시 무동작)" 0
else
  report "already-installed (재실행 시 무동작)" 1 "기대 exit=0 + 무출력 / 실제 exit=$status: $out"
fi

# 2. 지문 판정. 스크립트 본문에서 awk 식을 그대로 뽑아 쓴다(복제 금지 — 헤더 참조).
FPR_AWK=$(grep -oE "awk -F: '/\^pub:/.*want = 0 \} \}'" "$INSTALLER" | head -1)
if [ -z "$FPR_AWK" ]; then
  report "지문 추출식 확보" 1 "install-mise.sh 에서 awk 식을 찾지 못했습니다 — 판정 형태가 바뀌었으면 이 테스트도 함께 갱신하십시오."
else
  report "지문 추출식 확보" 0

  export GNUPGHOME="$TMP/gnupg"
  mkdir -p "$GNUPGHOME"
  chmod 700 "$GNUPGHOME"
  if gpg --batch --quiet --passphrase '' --quick-generate-key 'vendor <v@example.com>' default default never 2>/dev/null &&
    gpg --batch --quiet --passphrase '' --quick-generate-key 'rogue <r@example.com>' default default never 2>/dev/null; then

    EXPECTED=$(gpg --with-colons --fingerprint vendor 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')
    gpg --armor --export vendor >"$TMP/single.asc" 2>/dev/null
    gpg --armor --export vendor rogue >"$TMP/double.asc" 2>/dev/null
    gpg --armor --export rogue >"$TMP/wrong.asc" 2>/dev/null

    judge() { # $1=키링 -> 스크립트와 동일한 방식으로 뽑은 주 키 목록
      local raw
      raw=$(gpg --show-keys --with-colons "$1" 2>/dev/null)
      eval "$FPR_AWK" <<<"$raw"
    }

    # 정상: 기대 키 하나만 들어 있으면 통과해야 한다(오탐 회귀).
    [ "$(judge "$TMP/single.asc")" = "$EXPECTED" ] &&
      report "single-key (기대 키만 있으면 통과)" 0 ||
      report "single-key (기대 키만 있으면 통과)" 1 "판정=$(judge "$TMP/single.asc") / 기대=$EXPECTED"

    # 핵심: 기대 키 "와 함께" 다른 키가 섞여 들어오면 막아야 한다. 이 키링은 그대로
    # 서명 검증에 쓰이므로, 통과시키면 섞여 들어온 키로 서명된 설치 스크립트가
    # GOODSIG 로 승인된다. 예전의 "첫 fpr 일치" 방식은 여기서 통과했다(실측).
    [ "$(judge "$TMP/double.asc")" != "$EXPECTED" ] &&
      report "mixed-keys (키가 섞이면 차단)" 0 ||
      report "mixed-keys (키가 섞이면 차단)" 1 "섞인 키링이 통과했습니다 — 판정이 주 키 개수를 보지 않습니다"

    # 기본: 다른 키만 있으면 당연히 막아야 한다.
    [ "$(judge "$TMP/wrong.asc")" != "$EXPECTED" ] &&
      report "wrong-key (다른 키는 차단)" 0 ||
      report "wrong-key (다른 키는 차단)" 1 "판정=$(judge "$TMP/wrong.asc")"
  else
    report "합성 키링 생성" 1 "gpg 키 생성에 실패했습니다 — gnupg 설치 상태를 확인하십시오"
  fi
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
