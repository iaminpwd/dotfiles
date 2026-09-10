#!/usr/bin/env bash
# sudo 정책을 바꾸지 않고 Ansible 설치 또는 dry-run을 실행한다.
set -euo pipefail
ROOT=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)
cd "$ROOT"
export ANSIBLE_CONFIG="$ROOT/ansible/ansible.cfg"
export ANSIBLE_HOME="${ANSIBLE_HOME:-$HOME/.cache/ansible}"

# sudo-rs 프롬프트 호환성이 필요한 경우 이번 Ansible 프로세스만 classic sudo를 쓴다.
if [ -z "${ANSIBLE_BECOME_EXE:-}" ] && command -v sudo >/dev/null 2>&1 &&
  sudo --version 2>/dev/null | grep -qi sudo-rs && [ -x /usr/bin/sudo.ws ]; then
  export ANSIBLE_BECOME_EXE=/usr/bin/sudo.ws
fi

args=(-i "localhost," -c local ansible/site.yml)
# 비대화형 실행은 CI의 passwordless sudo 또는 외부에서 제공한 become 설정을 사용한다.
# 일반 터미널에서는 세션별 sudo 캐시 유무에 의존하지 않고 시작 시 비밀번호를 받는다.
if [ -t 0 ]; then
  args+=(--ask-become-pass)
fi
exec ansible-playbook "${args[@]}" "$@"
