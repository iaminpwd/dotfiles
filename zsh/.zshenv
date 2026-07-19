# mise shims PATH - 인터랙티브/비인터랙티브 셸(스크립트, 서브프로세스 등) 모두에서 로드됨.
# 전체 `mise activate`(cd 훅, 자동 env 전환 등)는 .zshrc에 그대로 두고,
# 여기서는 가벼운 PATH 등록만 수행해 비인터랙티브 실행 시 불필요한 side effect를 피한다.
export PATH="$HOME/.local/share/mise/shims:$PATH"
