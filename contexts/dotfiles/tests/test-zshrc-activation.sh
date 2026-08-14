#!/usr/bin/env bash
# test-zshrc-activation.sh
#
# stow/zsh/.zshrc 의 도구 활성화 블록(mise, fzf)은 두 결함이 조용히 되살아나기 쉬운 자리다.
#   1. 재실행 가드를 export 하면 환경 변수는 자식 프로세스로 상속되는데 activate 가 만드는
#      셸 함수/훅은 상속되지 않아, 중첩 zsh 나 `exec zsh` 에서 "가드는 켜져 있는데 훅은
#      없는" 상태가 된다. 그러면 디렉토리별 도구 버전 전환(mise)과 Ctrl-R/Ctrl-T
#      키바인딩(fzf)이 아무 에러 없이 사라진다. 하필 bootstrap.sh 의 마지막 안내가
#      `exec zsh` 이고 tmux/IDE 터미널도 전부 기존 셸에서 파생된다.
#   2. fzf 버전 게이트를 `printf "%d%03d"` 로 만든 문자열과 48000 처럼 자릿수가 안 맞는
#      임계값으로 비교하면, fzf 가 아직 0.x 라 어떤 버전에서도 게이트를 통과하지 못한다
#      (0.74.2 -> "0074"). 실측 결과 이 블록은 한 번도 실행된 적이 없었다.
# 둘 다 "조용히 아무 일도 안 일어나는" 형태의 실패라 사람이 알아채기 어려워 고정한다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-zshrc-activation.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
ZSHRC="$REPO_ROOT/stow/zsh/.zshrc"
ZSHENV="$REPO_ROOT/stow/zsh/.zshenv"

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

echo "=== .zshrc 도구 활성화 블록 회귀 테스트 ==="

# 1. 활성화 가드를 환경 변수로 export 하지 않는지(구조적 고정). zsh 가 없는 환경에서도
#    이 검사만은 항상 수행되어, 아래 기능 검사가 SKIP 되더라도 회귀는 잡힌다.
if grep -qE '^\s*export\s+(MISE|FZF)_ZSH_ACTIVATED' "$ZSHRC"; then
  report "no-exported-guard (활성화 가드를 export 하지 않음)" 1 \
    "$(grep -nE '^\s*export\s+(MISE|FZF)_ZSH_ACTIVATED' "$ZSHRC")"
else
  report "no-exported-guard (활성화 가드를 export 하지 않음)" 0
fi

# 2. 기능 검사: 낡은 가드를 환경에 물려받은 상태에서 중첩 zsh 를 띄워도 활성화가 되는가.
#    .zshrc 가 oh-my-zsh 를 source 하므로 그것까지 있어야 의미 있는 실행이 된다.
if ! command -v zsh >/dev/null 2>&1; then
  echo "  SKIP  nested-shell-activation (zsh 미설치)"
elif [ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
  echo "  SKIP  nested-shell-activation (oh-my-zsh 미설치)"
elif ! command -v mise >/dev/null 2>&1 || [ ! -x "$HOME/.local/bin/mise" ]; then
  echo "  SKIP  nested-shell-activation (mise 미설치)"
else
  # 사용자의 실제 ~/.zshrc 가 아니라 이 저장소의 원본을 SUT 로 삼기 위해 ZDOTDIR 로 격리한다.
  ZDOT="$TMP/zdot"
  mkdir -p "$ZDOT"
  cp "$ZSHRC" "$ZDOT/.zshrc"
  cp "$ZSHENV" "$ZDOT/.zshenv"

  PROBE="$TMP/probe.zsh"
  cat >"$PROBE" <<'PROBE_EOF'
_h=no
_f=no
typeset -f _mise_hook >/dev/null 2>&1 && _h=yes
typeset -f fzf-history-widget >/dev/null 2>&1 && _f=yes
echo "LEVEL${LVL} mise_hook=$_h fzf_widget=$_f"
PROBE_EOF

  # ZDOTDIR 은 바깥 zsh 의 환경에 들어가므로 중첩 zsh 도 그대로 물려받는다.
  # MISE/FZF_ZSH_ACTIVATED=1 은 "예전 방식으로 export 된 낡은 가드"를 재현한 것이다.
  OUT=$(ZDOTDIR="$ZDOT" MISE_ZSH_ACTIVATED=1 FZF_ZSH_ACTIVATED=1 \
    zsh -ic "LVL=1 source '$PROBE'; zsh -ic \"LVL=2 source '$PROBE'\"" 2>/dev/null || true)

  L1=$(grep -F 'LEVEL1' <<<"$OUT" || true)
  L2=$(grep -F 'LEVEL2' <<<"$OUT" || true)

  if grep -qF 'mise_hook=yes' <<<"$L1" && grep -qF 'mise_hook=yes' <<<"$L2"; then
    report "nested-shell-activation (중첩 셸에서도 mise 훅 유지)" 0
  else
    report "nested-shell-activation (중첩 셸에서도 mise 훅 유지)" 1 "L1='$L1' L2='$L2'"
  fi

  # [측정 기록] 재실행 가드(`! typeset -f _mise_hook`)를 없애 매번 activate 가 다시
  # 실행되게 만드는 뮤테이션은 이 스위트가 잡지 못하지만, 그건 커버리지 공백이 아니라
  # 그 뮤테이션이 무해하기 때문이다. mise activate 자체가 멱등이라 두 번 eval 해도
  # _mise_hook_precmd/_mise_hook_chpwd 가 각각 1개씩만 등록된다(실측). 즉 가드의 가치는
  # 중복 방지가 아니라 불필요한 재실행 회피(성능)이므로 동작으로 고정할 대상이 아니다.
  # 훅 이름도 _mise_hook 이 아니라 접미사가 붙은 두 개라는 점을 함께 남긴다.

  # 3. fzf 버전 게이트. fzf 0.48+ 가 설치돼 있는데도 위젯이 정의되지 않으면 임계값 비교가
  #    깨진 것이다(예전 48000 버그). fzf 가 없거나 구버전이면 검사 대상이 아니다.
  if command -v fzf >/dev/null 2>&1 &&
    [ "$(fzf --version 2>/dev/null | awk '{print $1}' | awk -F. '{print ($1 * 1000) + $2}')" -ge 48 ] 2>/dev/null; then
    if grep -qF 'fzf_widget=yes' <<<"$L1" && grep -qF 'fzf_widget=yes' <<<"$L2"; then
      report "fzf-version-gate (0.48+ 에서 fzf 키바인딩 활성화)" 0
    else
      report "fzf-version-gate (0.48+ 에서 fzf 키바인딩 활성화)" 1 "L1='$L1' L2='$L2'"
    fi
  else
    echo "  SKIP  fzf-version-gate (fzf 미설치 또는 0.48 미만)"
  fi
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
