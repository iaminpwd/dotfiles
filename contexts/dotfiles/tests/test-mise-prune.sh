#!/usr/bin/env bash
# test-mise-prune.sh
#
# ansible mise 역할(미사용 도구 버전 정리)의 실제 태스크를 임시 HOME과 가짜 mise
# 스텁으로 실행한다. 실제 홈의 mise는 호출하지 않는다(역할은 HOME/.local/bin/mise
# 절대 경로만 사용하고, 테스트는 ansible_env.HOME을 임시 디렉토리로 덮어쓴다).
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ANSIBLE_HOME="$TMP/ansible" ANSIBLE_LOCAL_TEMP="$TMP/local" ANSIBLE_REMOTE_TEMP="$TMP/remote"
if ! command -v ansible-playbook >/dev/null || ! ansible-playbook --version >/dev/null 2>&1; then
  echo '[WARNING] SKIP: ansible-playbook 필요 (mise prune 역할 테스트)'
  exit 0
fi
unset DOTFILES_MISE_PRUNE MISE_GLOBAL_CONFIG_FILE

FAIL=0
pass() { echo "PASS: $1"; }
fail() {
  echo "FAIL: $1"
  [ -f "$TMP/out" ] && sed 's/^/    /' "$TMP/out"
  FAIL=1
}

# role_path/../../../stow/... 가 정본을 가리키도록 저장소 구조를 축소 복제한다.
REPO="$TMP/repo"
mkdir -p "$REPO/ansible/roles/mise/tasks" "$REPO/stow/mise/.config/mise"
cp "$ROOT/ansible/roles/mise/tasks/main.yml" "$REPO/ansible/roles/mise/tasks/main.yml"
printf '[tools]\nnode = "24"\n' >"$REPO/stow/mise/.config/mise/config.toml"
export MISE_TEST_HOME="$TMP/home"
mkdir -p "$MISE_TEST_HOME/.local/bin" "$MISE_TEST_HOME/.config/mise"

cat >"$REPO/ansible/play.yml" <<'YAML'
- hosts: localhost
  gather_facts: false
  connection: local
  vars:
    ansible_env:
      HOME: "{{ lookup('env', 'MISE_TEST_HOME') }}"
      PATH: "{{ lookup('env', 'PATH') }}"
      MISE_GLOBAL_CONFIG_FILE: "{{ lookup('env', 'TEST_MISE_GLOBAL_CONFIG_FILE') }}"
  roles:
    - mise
YAML

cat >"$MISE_TEST_HOME/.local/bin/mise" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MISE_LOG"
case "$1" in
ls) printf '%s\n' "$PRUNABLE_JSON" ;;
prune)
  if [ "${PRUNE_FAIL:-0}" = 1 ]; then
    echo 'mise ERROR stub prune failure' >&2
    exit 1
  fi
  echo 'mise node@22.0.0 remove'
  ;;
*) exit 2 ;;
esac
STUB
chmod +x "$MISE_TEST_HOME/.local/bin/mise"
export MISE_LOG="$TMP/mise.log"
link_global() { ln -sfn "$1" "$MISE_TEST_HOME/.config/mise/config.toml"; }
link_global "$REPO/stow/mise/.config/mise/config.toml"

NONEMPTY='{"node":[{"version":"22.0.0"},{"version":"20.0.0"}],"uv":[{"version":"0.1.0"}]}'

# run <expected rc> [ansible-playbook args...] — 로그를 초기화하고 실행한다.
run() {
  local want=$1 rc=0
  shift
  : >"$MISE_LOG"
  (cd "$REPO/ansible" && ansible-playbook -i localhost, play.yml "$@") >"$TMP/out" 2>&1 || rc=$?
  [ "$rc" -eq "$want" ]
}
recap() { grep -oE "$1=[0-9]+" "$TMP/out" | tail -1 | cut -d= -f2; }
called() { grep -q "^$1" "$MISE_LOG"; }

if PRUNABLE_JSON=$NONEMPTY run 0 && called 'prune --tools --yes' && [ "$(recap changed)" = 1 ]; then
  pass '정리 대상이 있으면 prune --tools --yes 실행 후 changed'
else fail '정리 대상 prune 실행'; fi

if PRUNABLE_JSON='{}' run 0 && called 'ls --prunable --json' && ! called prune && [ "$(recap changed)" = 0 ]; then
  pass '정리 대상이 없으면 prune 미호출, changed=0 (멱등)'
else fail '정리 대상 없음 멱등성'; fi

if PRUNABLE_JSON=$NONEMPTY run 0 --check && called 'ls --prunable' && ! called prune && [ "$(recap changed)" = 1 ]; then
  pass '--check는 목록만 조회하고 삭제하지 않음(예정 changed 보고)'
else fail '--check 읽기 전용'; fi

if PRUNABLE_JSON=$NONEMPTY PRUNE_FAIL=1 run 0 && called prune && grep -q 'WARNING' "$TMP/out" && [ "$(recap rescued)" = 1 ]; then
  pass 'prune 실패는 경고 후 setup 계속(rescued)'
else fail 'prune 실패 경고 처리'; fi

if PRUNABLE_JSON='not-json' run 0 && ! called prune && [ "$(recap rescued)" = 1 ]; then
  pass '목록 파싱 실패 시 삭제하지 않고 경고'
else fail '목록 파싱 실패 처리'; fi

if DOTFILES_MISE_PRUNE=0 PRUNABLE_JSON=$NONEMPTY run 0 && [ ! -s "$MISE_LOG" ]; then
  pass 'DOTFILES_MISE_PRUNE=0이면 mise를 호출하지 않음'
else fail 'DOTFILES_MISE_PRUNE=0 비활성화'; fi

if TEST_MISE_GLOBAL_CONFIG_FILE="$TMP/other.toml" PRUNABLE_JSON=$NONEMPTY run 0 && [ ! -s "$MISE_LOG" ]; then
  pass 'MISE_GLOBAL_CONFIG_FILE이 정본이 아니면 건너뜀'
else fail 'MISE_GLOBAL_CONFIG_FILE 재지정 가드'; fi

printf '[tools]\n' >"$TMP/foreign.toml"
link_global "$TMP/foreign.toml"
if PRUNABLE_JSON=$NONEMPTY run 0 && [ ! -s "$MISE_LOG" ]; then
  pass '글로벌 설정이 다른 파일을 가리키면 건너뜀'
else fail '외부 글로벌 설정 가드'; fi
rm -f "$MISE_TEST_HOME/.config/mise/config.toml"
if PRUNABLE_JSON=$NONEMPTY run 0 && [ ! -s "$MISE_LOG" ]; then
  pass '글로벌 설정 링크가 없으면(최초 --check 등) 건너뜀'
else fail '링크 부재 가드'; fi

# 설치(bootstrap mise install)와 링크(stow) 이후에 정리하도록 역할 순서를 고정한다.
if awk '/- role: stow/{s=NR} /- role: mise/{m=NR} END{exit !(s && m && m > s)}' "$ROOT/ansible/site.yml"; then
  pass 'site.yml에서 mise 역할은 stow 이후'
else fail 'site.yml 역할 순서'; fi

exit "$FAIL"
