#!/usr/bin/env bash
# install-mise.sh - mise 설치 스크립트를 공식 GPG 키로 검증한 뒤 실행하는 공용 진입점 (SSOT)
#
# bootstrap.sh(로컬 셋업)와 .github/workflows/ci.yml(verify job)이 둘 다 mise 를 설치하는데,
# 예전엔 전자만 GPG 검증을 하고 후자는 `curl -fsSL https://mise.run | sh` 를 그대로 실행했다.
# 그러면 같은 저장소가 두 가지 신뢰 수준으로 도구를 들이게 되고, CI 는 검증 없이 받은 mise 로
# 그 저장소의 검증 스위트 전체를 돌린다. 공급망 판정을 한 곳에 모아 양쪽이 같은 경로를 쓴다.
#
# 이미 설치돼 있으면(재실행·캐시 복원) 아무것도 하지 않는다 — 두 호출부 모두 멱등 실행이 전제다.
#
# 사용: bash bin/utils/install-mise.sh
# 종료 코드: 0=설치 완료 또는 이미 존재, 1=공급망 검증 실패(Hard Block)

set -euo pipefail

if [ -x "$HOME/.local/bin/mise" ]; then
  exit 0
fi

echo "=> Installing mise (GPG 서명 검증 후 설치, https://mise.jdx.dev)..."
MISE_GPG_HOME="$(mktemp -d)"
MISE_INSTALL_SCRIPT="$MISE_GPG_HOME/install.sh"
# https://mise.jdx.dev/installing-mise.html 에 명시된 mise 릴리스 서명 키 지문
MISE_GPG_KEY_FP="24853EC9F655CE80B48E6C3A8B81C9D17413A06D"

curl -fsSL https://mise.jdx.dev/gpg-key.pub | gpg --homedir "$MISE_GPG_HOME" --import -q

# awk 를 파이프 오른쪽에 두고 exit 로 조기 종료시키지 않는다. awk 가 첫 fpr 에서 끝나며
# stdin 을 닫으면 gpg 가 SIGPIPE(141)로 죽고, set -o pipefail 이 그것을 파이프라인 결과로
# 채택해 이 대입이 실패한 뒤 set -e 가 스크립트를 죽인다 — 공급망 검증 직전에 아무 메시지
# 없이 중단되는 형태다. 지금은 키 1개짜리 출력이 파이프 버퍼(64KB)에 들어가 발현되지
# 않지만, 구조는 이 저장소가 db-sg-checker.sh / aws/tests/run.sh / prompt-lint.sh /
# test-coverage-check.sh 네 곳에서 이미 제거한 함정과 동일하다. 출력을 먼저 받아 파이프를
# 없애고, awk 는 exit 없이 매치를 모아 둔다.
#
# 첫 fpr 하나만 보면 안 된다. 내려받은 키 뭉치에 기대 키 "와 함께" 다른 키가 들어 있으면
# 첫 fpr 은 여전히 기대값이라 통과하는데, 그 키링은 아래 서명 검증에 그대로 쓰이므로
# 섞여 들어온 키로 서명된 설치 스크립트가 GOODSIG 로 승인된다(실측: 두 키를 합쳐 export
# 한 키링에서 "첫 fpr 일치" 방식이 통과). 주 키(pub 레코드 바로 뒤의 fpr)만 뽑아
# "정확히 1개이고 그것이 기대값"인지를 본다 — 서브키 fpr 은 세지 않는다.
# (ansible docker 롤의 지문 검증도 같은 이유로 같은 형태다.)
MISE_GPG_FPR_RAW="$(gpg --homedir "$MISE_GPG_HOME" --with-colons --fingerprint)"
IMPORTED_FP="$(awk -F: '/^pub:/ { want = 1; next } /^fpr:/ { if (want) { print $10; want = 0 } }' <<<"$MISE_GPG_FPR_RAW")"
if [ "$IMPORTED_FP" != "$MISE_GPG_KEY_FP" ]; then
  echo "❌ [Hard Block] mise GPG 키 지문이 예상 값과 다릅니다 (공급망 검증 실패)." >&2
  echo "   기대: $MISE_GPG_KEY_FP (주 키 정확히 1개)" >&2
  echo "   실제: ${IMPORTED_FP:-(주 키 없음)}" >&2
  rm -rf "$MISE_GPG_HOME"
  exit 1
fi

# 검증 판정에 사람용 출력("Good signature from")을 쓰지 않는다. 두 가지 문제가 있었다:
#   1. 그 문구는 gpg 의 번역 대상이라 로케일에 따라 달라진다(gnupg 에 ko 번역이 없어
#      한국어 환경에서는 우연히 영어가 나왔을 뿐, ja/de 등에서는 정상 서명도 실패 판정).
#   2. 파이프라인 실패를 잡지 않아, 서명이 실제로 틀렸을 때 gpg 가 0 이 아닌 코드로
#      끝나면 set -euo pipefail 이 바로 아래 안내 문구에 닿기도 전에 스크립트를 죽였다
#      — 즉 정작 필요한 Hard Block 메시지가 한 번도 출력될 수 없었다.
# --status-fd 로 나오는 기계용 상태 줄(GOODSIG)은 번역되지 않으므로 이쪽을 판정에 쓴다.
gpg_rc=0
curl -fsSL https://mise.jdx.dev/install.sh.sig |
  gpg --homedir "$MISE_GPG_HOME" --status-fd 3 --decrypt \
    >"$MISE_INSTALL_SCRIPT" 3>"$MISE_GPG_HOME/status.log" 2>"$MISE_GPG_HOME/verify.log" || gpg_rc=$?
if [ "$gpg_rc" -ne 0 ] || ! grep -q '^\[GNUPG:\] GOODSIG ' "$MISE_GPG_HOME/status.log"; then
  echo "❌ [Hard Block] mise 설치 스크립트 GPG 서명 검증 실패." >&2
  cat "$MISE_GPG_HOME/verify.log" >&2
  rm -rf "$MISE_GPG_HOME"
  exit 1
fi

sh "$MISE_INSTALL_SCRIPT"
rm -rf "$MISE_GPG_HOME"
