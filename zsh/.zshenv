# mise shims PATH - 인터랙티브/비인터랙티브 셸(스크립트, 서브프로세스 등) 모두에서 로드됨.
# 전체 `mise activate`(cd 훅, 자동 env 전환 등)는 .zshrc에 그대로 두고,
# 여기서는 가벼운 PATH 등록만 수행해 비인터랙티브 실행 시 불필요한 side effect를 피한다.
# PATH 중복 누적 방지. 이 파일은 비인터랙티브 셸(스크립트, 서브프로세스)까지 포함해
# 모든 zsh 호출마다 로드되므로, 멱등 가드 없이 prepend 하면 셸이 중첩될 때마다 같은
# 경로가 쌓인다(2026-07-28 실측: 1단계 shims 중복 4개 -> 2단계 5개, PATH 3.5KB).
# 020-shell-scripting-standard.md 의 [MUST] Explicit Idempotency 위반이었다.
# typeset -U 는 아래 prepend 뿐 아니라 .zshrc 의 추가와 mise activate 가 넣는 경로까지
# 한 번에 덮으므로, 라인마다 grep 가드를 다는 것보다 확실하고 단순하다.
# (선두 우선으로 중복을 제거하므로 prepend 의 우선순위 의도도 그대로 유지된다.)
typeset -U path PATH

# macOS: GNU 툴체인을 BSD 기본 도구보다 앞에 둔다.
# 이 저장소의 검증기(pre-flight-check.sh, prompt-lint.sh, 회귀 스위트)는 readlink -f,
# find -printf, sha256sum, sed -i, xargs -r 처럼 GNU 전용 인터페이스를 쓴다. BSD 판으로
# 하나씩 우회하면 검증 로직을 OS별로 갈라 놓아야 해서, 도구를 맞추는 쪽을 택했다.
# brew --prefix 호출은 셸이 열릴 때마다 프로세스를 띄우므로 쓰지 않고 경로를 직접 확인한다.
if [[ "$OSTYPE" == darwin* ]]; then
  for _brew_prefix in /opt/homebrew /usr/local; do
    [[ -d "$_brew_prefix/opt" ]] || continue
    for _gnu_pkg in coreutils gnu-sed findutils grep; do
      [[ -d "$_brew_prefix/opt/$_gnu_pkg/libexec/gnubin" ]] &&
        path=("$_brew_prefix/opt/$_gnu_pkg/libexec/gnubin" $path)
    done
    break
  done
  unset _brew_prefix _gnu_pkg
fi

export PATH="$HOME/.local/share/mise/shims:$PATH"
