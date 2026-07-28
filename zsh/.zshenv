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

export PATH="$HOME/.local/share/mise/shims:$PATH"
