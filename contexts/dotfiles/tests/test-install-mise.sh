#!/usr/bin/env bash
# test-install-mise.sh
#
# bin/utils/install-mise.sh 는 bootstrap.sh(로컬 셋업)와 ci.yml(verify job)이 공유하는
# mise 설치 진입점이다. 이 스크립트가 하는 일은 사실상 "공식 GPG 키로 설치 스크립트
# 서명을 검증한다" 하나이므로, 그 판정이 느슨해지면 검증 없이 임의 코드를 실행하는
# 경로가 된다 — 검증이 죽어도 설치는 성공하니 아무도 모른다.
#
# 실제 설치는 네트워크에 의존하므로 여기서 반복하지 않는다. 대신 네트워크 없이 확인
# 가능한 축을 고정한다: (1) 고정 mise 버전이 이미 설치돼 있으면 무동작(멱등),
# (1a) 다른 mise 버전은 이미 설치돼 있어도 고정 버전 설치 경로로 들어간다,
# (1b) 설치가 필요한데 검증을 못 하면 조용히 통과하지 않는다,
# (2) 지문 판정이 "주 키가 정확히 1개이고 기대값"인가,
# (3) 정상 설치 시 공식 installer에 저장소의 MISE_VERSION pin을 실제로 전달하는가.
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

PINNED_VERSION=$(grep -oE '^MISE_VERSION="[0-9.]+"' "$INSTALLER" | head -1 | sed -E 's/.*"([^"]+)"/\1/')
if [ -z "$PINNED_VERSION" ]; then
  echo "FAIL: install-mise.sh 에서 고정 MISE_VERSION을 찾지 못했습니다." >&2
  exit 1
fi

# 1. 멱등: 정확히 고정된 mise 버전이 있으면 네트워크를 타지 않고 즉시 0.
IDEM_HOME="$TMP/idem"
mkdir -p "$IDEM_HOME/.local/bin"
printf '#!/bin/sh\nprintf "%s linux-x64\\n"\n' "$PINNED_VERSION" >"$IDEM_HOME/.local/bin/mise"
chmod +x "$IDEM_HOME/.local/bin/mise"

status=0
out=$(HOME="$IDEM_HOME" bash "$INSTALLER" 2>&1) || status=$?
if [ "$status" -eq 0 ] && [ -z "$out" ]; then
  report "already-pinned (같은 버전 재실행 시 무동작)" 0
else
  report "already-pinned (같은 버전 재실행 시 무동작)" 1 "기대 exit=0 + 무출력 / 실제 exit=$status: $out"
fi

# 1a. 실행 파일이 존재한다는 이유만으로 통과하면 머신마다 mise 버전이 달라진다.
#     다른 버전을 둔 뒤 curl을 막아, 조기 종료하지 않고 재설치 경로로 진입하는지 고정한다.
MISMATCH_HOME="$TMP/mismatch"
mkdir -p "$MISMATCH_HOME/.local/bin" "$TMP/mismatch-bin"
printf '#!/bin/sh\nprintf "2000.1.1 linux-x64\\n"\n' >"$MISMATCH_HOME/.local/bin/mise"
printf '#!/bin/sh\nexit 1\n' >"$TMP/mismatch-bin/curl"
chmod +x "$MISMATCH_HOME/.local/bin/mise" "$TMP/mismatch-bin/curl"

status=0
out=$(HOME="$MISMATCH_HOME" PATH="$TMP/mismatch-bin:$PATH" bash "$INSTALLER" 2>&1) || status=$?
if [ "$status" -ne 0 ] && [[ "$out" == *"고정 버전 $PINNED_VERSION"* ]]; then
  report "version-mismatch (다른 mise는 고정 버전 설치 경로 진입)" 0
else
  report "version-mismatch (다른 mise는 고정 버전 설치 경로 진입)" 1 "기대 재설치 시도 후 실패 / 실제 exit=$status: $out"
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

# 1c. mktemp 이후 첫 공급망 fetch가 set -e로 조기 실패해도 임시 GPG 홈을 남기면 안 된다.
#     고정 경로를 돌려주는 mktemp stub으로 cleanup 여부를 직접 관찰한다.
CLEANUP_HOME="$TMP/cleanup-home"
CLEANUP_BIN="$TMP/cleanup-bin"
CLEANUP_GPG_HOME="$TMP/forced-mise-gpg-home"
mkdir -p "$CLEANUP_HOME" "$CLEANUP_BIN"
cat >"$CLEANUP_BIN/mktemp" <<'STUB'
#!/usr/bin/env bash
mkdir -p "$STUB_MKTEMP_DIR"
printf '%s\n' "$STUB_MKTEMP_DIR"
STUB
cat >"$CLEANUP_BIN/curl" <<'STUB'
#!/usr/bin/env bash
exit 22
STUB
chmod +x "$CLEANUP_BIN/mktemp" "$CLEANUP_BIN/curl"

status=0
out=$(HOME="$CLEANUP_HOME" PATH="$CLEANUP_BIN:$PATH" STUB_MKTEMP_DIR="$CLEANUP_GPG_HOME" bash "$INSTALLER" 2>&1) || status=$?
if [ "$status" -ne 0 ] && [ ! -e "$CLEANUP_GPG_HOME" ]; then
  report "early-failure-cleanup (조기 실패에도 GPG tempdir 제거)" 0
else
  report "early-failure-cleanup (조기 실패에도 GPG tempdir 제거)" 1 \
    "exit=$status tempdir_exists=$(test -e "$CLEANUP_GPG_HOME" && echo yes || echo no) out=$out"
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

  # sh 스텁: installer 실행 흔적을 남기고, 기본값에서는 실제 설치 결과처럼
  # ~/.local/bin/mise도 만든다. STUB_CREATE_MISE=0이면 installer가 exit 0만 하고
  # 바이너리를 만들지 않는 "거짓 성공"을 재현한다.
  cat >"$E2E_BIN/sh" <<'STUB'
#!/usr/bin/env bash
printf 'ran:%s\n' "${MISE_VERSION:-}" >"$STUB_MARKER"
if [ "${STUB_CREATE_MISE:-1}" = "1" ]; then
  mkdir -p "$HOME/.local/bin"
  cat >"$HOME/.local/bin/mise" <<EOF
#!/bin/sh
printf '%s linux-x64\\n' "${MISE_VERSION:-}"
EOF
  chmod +x "$HOME/.local/bin/mise"
fi
exit 0
STUB
  chmod +x "$E2E_BIN/curl" "$E2E_BIN/gpg" "$E2E_BIN/sh"

  # run_e2e <지문목록> <GOODSIG여부> [mise생성여부]
  # -> "<exit코드>|<설치실행여부>|<출력>"
  run_e2e() {
    local fps=$1 goodsig=$2 create_mise=${3:-1} home marker st out
    home="$TMP/e2e-home-$RANDOM"
    marker="$TMP/e2e-marker-$RANDOM"
    mkdir -p "$home"
    st=0
    out=$(HOME="$home" PATH="$E2E_BIN:$PATH" STUB_FPS="$fps" STUB_GOODSIG="$goodsig" \
      STUB_MARKER="$marker" STUB_CREATE_MISE="$create_mise" bash "$INSTALLER" 2>&1) || st=$?
    if [ -e "$marker" ]; then echo "$st|$(cat "$marker")|$out"; else echo "$st|blocked|$out"; fi
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
  if [ "${r%%|*}" -eq 0 ] && [[ "$r" == *"|ran:$PINNED_VERSION|"* ]]; then
    report "e2e happy-path (고정 mise 버전으로 설치 진행)" 0
  else
    report "e2e happy-path (고정 mise 버전으로 설치 진행)" 1 "$r"
  fi

  # 3e. 서명도 맞고 installer 자체가 exit 0이어도 실제 mise 바이너리가 생성되지 않았다면
  # install-mise.sh가 성공을 반환하면 안 된다. 이 스크립트의 0 계약은 "설치 완료 또는
  # 이미 존재"이므로, installer의 종료 코드가 아니라 결과 바이너리/버전까지 종단 검증한다.
  r=$(run_e2e "$REAL_FP" 1 0)
  if [ "${r%%|*}" -ne 0 ] &&
    [[ "$r" == *"|ran:$PINNED_VERSION|"* ]] &&
    [[ "$r" == *"설치 결과 검증 실패"* ]]; then
    report "e2e installer-false-success (바이너리 미생성은 Hard Block)" 0
  else
    report "e2e installer-false-success (바이너리 미생성은 Hard Block)" 1 "$r"
  fi
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
