# mise shims PATH 등록 (비인터랙티브 셸 포함)
# 무거운 activate 기능은 .zshrc에 남겨 부작용 최소화
# PATH 중복 누적 방지 (멱등성 보장): typeset -U 로 PATH 전역 중복 제거 적용
if [ -n "${ZSH_VERSION:-}" ]; then
  typeset -U path PATH
fi

# macOS: 검증기 스크립트 호환성을 위해 GNU 툴체인을 우선 적용 (BSD 우회)
# 속도 저하 방지를 위해 brew --prefix 호출 없이 경로 직접 검사
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
