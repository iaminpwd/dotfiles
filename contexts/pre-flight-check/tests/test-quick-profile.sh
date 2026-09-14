#!/usr/bin/env bash
# 실제 오케스트레이터에 검증기 스텁을 연결해 quick/full의 실행 범위를 확인한다.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo/bin/hooks/plugins" "$TMP/repo/bin/lib" "$TMP/tools"
cp "$ROOT/bin/hooks/pre-flight-check.sh" "$TMP/repo/bin/hooks/"
cp "$ROOT/bin/lib/script-init.sh" "$ROOT/bin/lib/tool-probe.sh" "$TMP/repo/bin/lib/"
git -C "$TMP/repo" init -q
printf 'resource "test" "example" {}\n' >"$TMP/repo/main.tf"
printf 'kind: Test\n' >"$TMP/repo/main.yaml"
export PROFILE_TRACE="$TMP/trace"

for module in pfc-iac-checks pfc-quality-checks; do
  : >"$TMP/repo/bin/lib/$module.sh"
done
for check in shell terraform sam ansible helm k8s_manifests docker yaml conftest security finops_costs; do
  # shellcheck disable=SC2016
  printf 'validate_%s() { echo %s >>"$PROFILE_TRACE"; [ "${FAIL_CHECK:-}" != %s ]; }\n' \
    "$check" "$check" "$check" >>"$TMP/repo/bin/lib/pfc-quality-checks.sh"
done
cat >>"$TMP/repo/bin/lib/pfc-quality-checks.sh" <<'EOF'
has_tool() { return 0; }
EOF
cat >"$TMP/tools/terraform" <<'EOF'
#!/usr/bin/env bash
printf 'terraform %s\n' "$*" >>"$PROFILE_TRACE"
EOF
chmod +x "$TMP/tools/terraform"
export PATH="$TMP/tools:$PATH"
PFC="$TMP/repo/bin/hooks/pre-flight-check.sh"

cat >"$TMP/repo/bin/hooks/plugins/test-plugin.sh" <<'EOF'
#!/usr/bin/env bash
echo plugin >>"$PROFILE_TRACE"
EOF
PFC_PROFILE=quick bash "$PFC" "$TMP/repo/main.tf" "$TMP/repo/main.yaml"
printf 'shell\nyaml\ndocker\nterraform fmt -check %s/main.tf\n' "$TMP/repo" >"$TMP/expected"
diff -u "$TMP/expected" "$PROFILE_TRACE"
echo 'PASS quick: 문법·포맷 검사만 호출'

: >"$PROFILE_TRACE"
PFC_PROFILE=stop bash "$PFC" "$TMP/repo/main.tf" "$TMP/repo/main.yaml"
printf 'shell\nyaml\ndocker\nansible\nterraform fmt -check %s/main.tf\n' "$TMP/repo" >"$TMP/expected"
diff -u "$TMP/expected" "$PROFILE_TRACE"
echo 'PASS stop: 변경 파일·Ansible만 검사하고 전체 보안·도메인 검사는 제외'

: >"$PROFILE_TRACE"
PFC_DOMAIN_CHECKS=0 PFC_PROFILE=full bash "$PFC" "$TMP/repo/main.tf" "$TMP/repo/main.yaml"
printf 'shell\nansible\ndocker\nyaml\nsecurity\n' >"$TMP/expected"
diff -u "$TMP/expected" "$PROFILE_TRACE"
echo 'PASS full 기본: 보안 검사 유지, 도메인 정책은 자동 실행하지 않음'

: >"$PROFILE_TRACE"
PFC_DOMAIN_CHECKS=1 PFC_PROFILE=full bash "$PFC" "$TMP/repo/main.tf" "$TMP/repo/main.yaml"
for check in shell terraform sam ansible helm k8s_manifests docker yaml conftest security finops_costs; do
  grep -qxF "$check" "$PROFILE_TRACE"
done
grep -qxF plugin "$PROFILE_TRACE"
echo 'PASS full: 전체 검증 경로 유지'

# 기본 full이 실행하지 않은 Terraform 검사를 성공 캐시로 기록해서는 안 된다.
git -C "$TMP/repo" add main.tf
(cd "$TMP/repo" && PFC_DOMAIN_CHECKS=0 PFC_PROFILE=full bash "$PFC")
[ ! -f "$TMP/repo/.pre-flight-check.cache" ]
echo 'PASS 기본 full: 미실행 도메인 검사는 성공 캐시를 만들지 않음'

if FAIL_CHECK=shell PFC_PROFILE=quick bash "$PFC" "$TMP/repo/main.tf" "$TMP/repo/main.yaml"; then
  echo 'FAIL quick 검사 오류가 통과됨' >&2
  exit 1
fi
echo 'PASS quick: 검사 실패 전파'

if PFC_PROFILE=invalid bash "$PFC" "$TMP/repo/main.tf" "$TMP/repo/main.yaml" >/dev/null 2>&1; then
  echo 'FAIL 잘못된 프로필이 통과됨' >&2
  exit 1
fi
echo 'PASS 잘못된 프로필 차단'

# 실제 Docker 검증 함수도 quick에서는 하드닝 스캐너를 부르지 않는다.
PFC_SCRIPT_DIR="$TMP/repo/bin/hooks"
(
  source "$ROOT/bin/lib/pfc-quality-checks.sh"
  mkdir -p "$TMP/repo/bin/linters"
  cat >"$TMP/repo/bin/linters/container-hardening-gate.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  filter_target_files() { printf '%s\0' "$TMP/repo/Dockerfile"; }
  has_tool() { return 0; }
  log_info() { :; }
  hadolint() { return 0; }
  PFC_PROFILE=quick validate_docker
  PFC_PROFILE=stop validate_docker
  if PFC_PROFILE=full validate_docker >/dev/null 2>&1; then
    echo 'FAIL full 하드닝 실패가 무시됨' >&2
    exit 1
  fi
)
echo 'PASS Docker: quick은 린트만, full은 하드닝 검사 유지'

# 실제 Ansible 함수에 도구 스텁을 붙여 Stop에서 변경 파일 인자가 전달되는지 확인한다.
(
  cd "$TMP/repo"
  source "$ROOT/bin/lib/pfc-iac-checks.sh"
  filter_target_files() {
    case "$1" in
    '*roles/*') printf '%s\0' 'roles/demo/tasks/main.yml' ;;
    *) printf '%s\0' 'playbook.yml' ;;
    esac
  }
  has_tool() { return 0; }
  log_info() { :; }
  ansible-playbook() { :; }
  # shellcheck disable=SC2329 # validate_ansible의 lint_cmd 배열을 통해 호출한다.
  ansible-lint() { printf '%s\n' "$@" >"$TMP/ansible-args"; }
  PFC_PROFILE=stop validate_ansible
  printf 'playbook.yml\nroles/demo/tasks/main.yml\n' >"$TMP/expected-ansible"
  diff -u "$TMP/expected-ansible" "$TMP/ansible-args"
)
echo 'PASS Stop Ansible: 변경 플레이북·롤 파일만 린트에 전달'
