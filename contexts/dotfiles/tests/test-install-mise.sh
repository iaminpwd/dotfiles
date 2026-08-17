#!/usr/bin/env bash
# test-install-mise.sh
#
# bin/utils/install-mise.sh 는 bootstrap.sh(로컬 셋업)와 ci.yml(verify job)이 공유하는
# mise 설치 진입점이다. 이 스크립트가 하는 일은 사실상 "공식 GPG 키로 설치 스크립트
# 서명을 검증한다" 하나이므로, 그 판정이 느슨해지면 검증 없이 임의 코드를 실행하는
# 경로가 된다 — 검증이 죽어도 설치는 성공하니 아무도 모른다.
#
# 실제 설치는 네트워크에 의존하므로 여기서 반복하지 않는다. 대신 네트워크 없이 확인
# 가능한 세 축을 고정한다: (1) 이미 설치돼 있으면 아무것도 하지 않는다(멱등),
# (1b) 설치가 필요한데 검증을 못 하면 조용히 통과하지 않는다,
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

# 1b. 설치가 필요한 상태에서 네트워크가 막히면 반드시 시끄럽게 실패해야 한다.
#     1번(멱등)과 2번(지문 판정)만으로는 "스크립트가 통째로 아무 일도 안 하게 된" 경우를
#     구분하지 못한다 — 껍데기도 exit 0 무출력이고, 지문 식은 파일에 텍스트로 남아 있어
#     정적 추출도 그대로 성공한다(실측: 즉시 exit 0 을 심어도 이 스위트가 통과했다).
#     curl 을 실패하게 만든 뒤 exit≠0 을 요구하면 그 축이 닫힌다.
BLOCKED_HOME="$TMP/blocked"
mkdir -p "$BLOCKED_HOME" "$TMP/fakebin"
printf '#!/bin/sh\nexit 1\n' >"$TMP/fakebin/curl"
chmod +x "$TMP/fakebin/curl"

status=0
out=$(HOME="$BLOCKED_HOME" PATH="$TMP/fakebin:$PATH" bash "$INSTALLER" 2>&1) || status=$?
if [ "$status" -ne 0 ]; then
  report "network-blocked (검증 불가 시 조용히 통과하지 않음)" 0
else
  report "network-blocked (검증 불가 시 조용히 통과하지 않음)" 1 \
    "기대 exit≠0 / 실제 exit=0 — 설치도 검증도 못 했는데 성공으로 끝났습니다: $out"
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
    if [ "$(judge "$TMP/single.asc")" = "$EXPECTED" ]; then
      report "single-key (기대 키만 있으면 통과)" 0
    else
      report "single-key (기대 키만 있으면 통과)" 1 "판정=$(judge "$TMP/single.asc") / 기대=$EXPECTED"
    fi

    # 핵심: 기대 키 "와 함께" 다른 키가 섞여 들어오면 막아야 한다. 이 키링은 그대로
    # 서명 검증에 쓰이므로, 통과시키면 섞여 들어온 키로 서명된 설치 스크립트가
    # GOODSIG 로 승인된다. 예전의 "첫 fpr 일치" 방식은 여기서 통과했다(실측).
    if [ "$(judge "$TMP/double.asc")" != "$EXPECTED" ]; then
      report "mixed-keys (키가 섞이면 차단)" 0
    else
      report "mixed-keys (키가 섞이면 차단)" 1 "섞인 키링이 통과했습니다 — 판정이 주 키 개수를 보지 않습니다"
    fi

    # 기본: 다른 키만 있으면 당연히 막아야 한다.
    if [ "$(judge "$TMP/wrong.asc")" != "$EXPECTED" ]; then
      report "wrong-key (다른 키는 차단)" 0
    else
      report "wrong-key (다른 키는 차단)" 1 "판정=$(judge "$TMP/wrong.asc")"
    fi
  else
    report "합성 키링 생성" 1 "gpg 키 생성에 실패했습니다 — gnupg 설치 상태를 확인하십시오"
  fi
fi

# 3. 판정 "결과로 실제 설치를 막는가" (종단 검증).
#
# 위 2번은 awk 추출식을 격리해서 "섞인 키링을 올바로 판별하는가"만 본다. 정작 그 판별을
# 받아 설치를 중단시키는 4줄(지문 비교 -> Hard Block -> exit 1)은 어느 케이스도 실행하지
# 않았다 — 실측: `if [ "$IMPORTED_FP" != "$MISE_GPG_KEY_FP" ]` 을 `if false` 로 바꿔도 이
# 스위트가 전부 통과했다. 게다가 1번(멱등)이 조기 종료 경로라, mise 가 이미 설치된 환경
# (=개발자 머신과 CI 대부분)에서는 본체에 도달조차 하지 않는다.
#
# 네트워크 없이 본체를 끝까지 태우기 위해 curl/gpg/sh 를 PATH 앞에 스텁으로 둔다. gpg
# 스텁이 내보낼 지문과 서명 상태를 환경변수로 조종해 네 시나리오를 만든다. 기대 지문은
# 스크립트에서 뽑아 쓴다(상수를 복제하면 본체만 바뀌었을 때 테스트가 조용히 낡는다).
REAL_FP=$(grep -oE 'MISE_GPG_KEY_FP="[0-9A-Fa-f]+"' "$INSTALLER" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')
if [ -z "$REAL_FP" ]; then
  report "기대 지문 상수 확보" 1 "install-mise.sh 에서 MISE_GPG_KEY_FP 를 찾지 못했습니다"
else
  report "기대 지문 상수 확보" 0

  E2E_BIN="$TMP/e2ebin"
  mkdir -p "$E2E_BIN"

  printf '#!/usr/bin/env bash\necho STUB-PAYLOAD\nexit 0\n' >"$E2E_BIN/curl"

  # gpg 스텁: --import / --fingerprint / --decrypt 세 호출을 인자로 구분한다.
  # fd 3 은 호출부가 `3>status.log` 로 열어 주므로 그대로 쓴다.
  cat >"$E2E_BIN/gpg" <<'STUB'
#!/usr/bin/env bash
mode=""
for a in "$@"; do
  case "$a" in
  --import) mode=import ;;
  --fingerprint) mode=fpr ;;
  --decrypt) mode=decrypt ;;
  esac
done
case "$mode" in
import)
  cat >/dev/null
  ;;
fpr)
  # STUB_FPS 는 공백 구분 목록이다. 여러 개면 "키가 섞인 키링"을 재현한다.
  for fp in ${STUB_FPS:-}; do
    echo "pub:u:255:22:0000000000000000:1700000000:::u:::scESC::::::23::0:"
    echo "fpr:::::::::${fp}:"
  done
  ;;
decrypt)
  cat >/dev/null
  echo '#!/bin/sh'
  echo 'echo stub-installer'
  if [ "${STUB_GOODSIG:-1}" = "1" ]; then
    echo '[GNUPG:] GOODSIG 0000000000000000 vendor <v@example.com>' >&3
  else
    echo '[GNUPG:] BADSIG 0000000000000000 rogue <r@example.com>' >&3
    echo 'gpg: BAD signature from "rogue"' >&2
    exit 1
  fi
  ;;
esac
exit 0
STUB

  # sh 스텁: "설치가 실제로 실행됐다"의 유일한 증거. 차단 케이스에서는 생기면 안 된다.
  # 홑따옴표가 맞다 — $STUB_MARKER 는 지금이 아니라 스텁이 실행되는 시점에 전개돼야 한다.
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\necho ran >"$STUB_MARKER"\nexit 0\n' >"$E2E_BIN/sh"
  chmod +x "$E2E_BIN/curl" "$E2E_BIN/gpg" "$E2E_BIN/sh"

  # run_e2e <지문목록> <GOODSIG여부> -> "<exit코드>|<설치실행여부>|<출력>"
  run_e2e() {
    local fps=$1 goodsig=$2 home marker st out
    home="$TMP/e2e-home-$RANDOM"
    marker="$TMP/e2e-marker-$RANDOM"
    mkdir -p "$home"
    st=0
    out=$(HOME="$home" PATH="$E2E_BIN:$PATH" STUB_FPS="$fps" STUB_GOODSIG="$goodsig" \
      STUB_MARKER="$marker" bash "$INSTALLER" 2>&1) || st=$?
    if [ -e "$marker" ]; then echo "$st|ran|$out"; else echo "$st|blocked|$out"; fi
  }

  # 3a. 지문 불일치 -> 차단, 설치 미실행.
  r=$(run_e2e "DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF" 1)
  if [ "${r%%|*}" -ne 0 ] && [[ "$r" == *"|blocked|"* ]] && [[ "$r" == *"Hard Block"* ]]; then
    report "e2e wrong-fingerprint (차단 + 설치 미실행)" 0
  else
    report "e2e wrong-fingerprint (차단 + 설치 미실행)" 1 "$r"
  fi

  # 3b. 기대 키 "와 함께" 다른 키가 섞인 키링 -> 차단. 2번의 mixed-keys 를 종단으로 잇는다.
  r=$(run_e2e "$REAL_FP DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF" 1)
  if [ "${r%%|*}" -ne 0 ] && [[ "$r" == *"|blocked|"* ]]; then
    report "e2e mixed-keyring (섞인 키링 차단 + 설치 미실행)" 0
  else
    report "e2e mixed-keyring (섞인 키링 차단 + 설치 미실행)" 1 "$r"
  fi

  # 3c. 지문은 맞지만 서명이 불량(GOODSIG 없음) -> 차단. 두 번째 하드 블록이다.
  r=$(run_e2e "$REAL_FP" 0)
  if [ "${r%%|*}" -ne 0 ] && [[ "$r" == *"|blocked|"* ]] && [[ "$r" == *"서명 검증 실패"* ]]; then
    report "e2e bad-signature (서명 불량 차단 + 설치 미실행)" 0
  else
    report "e2e bad-signature (서명 불량 차단 + 설치 미실행)" 1 "$r"
  fi

  # 3d. 정상 경로 -> 설치 진행. 이 케이스가 없으면 "항상 차단"으로 바뀌어도 3a~3c 가 전부
  #     통과해 게이트가 고장난 채 초록불이 된다(차단 전용 테스트만 두면 생기는 사각지대).
  r=$(run_e2e "$REAL_FP" 1)
  if [ "${r%%|*}" -eq 0 ] && [[ "$r" == *"|ran|"* ]]; then
    report "e2e happy-path (검증 통과 시 설치 진행)" 0
  else
    report "e2e happy-path (검증 통과 시 설치 진행)" 1 "$r"
  fi
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
