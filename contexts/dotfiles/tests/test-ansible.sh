#!/usr/bin/env bash
# test-ansible.sh
#
# validate_ansible(pre-flight-check.sh)는 이전까지 어떤 fixture 테스트도 없었다.
# 이 저장소의 실제 ansible 사용처(ansible/site.yml, bootstrap.sh)와 가장 밀접한
# 워크스페이스라 dotfiles에 둔다.
#
# ansible-playbook --syntax-check는 파일 인자를 직접 받지만, ansible-lint는 인자
# 없이 현재 디렉토리를 통째로 스캔한다(pre-flight-check.sh의 validate_ansible과
# 동일). 그래서 lint 케이스만 격리된 디렉토리(lint-ok/, lint-fail/)로 따로 두고
# cd 해서 실행한다 — 그러지 않으면 이 저장소의 실제 ansible/ 디렉토리까지 스캔
# 범위에 들어와 픽스처 테스트가 무관한 결과에 흔들린다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/test-ansible.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$TESTS_DIR/fixtures-ansible"
# shellcheck source-path=SCRIPTDIR
source "$TESTS_DIR/../../.shared/test-lib/parallel-pair.sh"

PASS_COUNT=0
FAIL_COUNT=0

require_tool() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "  FAIL  도구 미설치: $1 — 'mise install $1' 후 다시 실행하십시오"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  return 1
}

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

echo "=== ansible 검증 회귀 테스트 ==="

# ansible-playbook/ansible-lint 둘 다 파이썬 인터프리터 기동 비용이 크고(이 스위트
# 소요 시간의 대부분을 ansible-lint가 차지) ok/fail 픽스처가 서로 무관하므로
# parallel-pair.sh(SSOT)로 동시에 돌린다.
PAIR_TMPDIR=$(mktemp -d)
trap 'rm -rf "${PAIR_TMPDIR:-}"' EXIT

echo "--- ansible-playbook --syntax-check ---"
if require_tool ansible-playbook; then
  # shellcheck disable=SC2034 # parallel_pair_run 안에서 nameref로 간접 참조됨
  CMD_OK=(ansible-playbook --syntax-check "$FIXTURES/ok-playbook.yml")
  # shellcheck disable=SC2034
  CMD_FAIL=(ansible-playbook --syntax-check "$FIXTURES/fail-syntax-playbook.yml")
  ok_status=0
  fail_status=0
  parallel_pair_run CMD_OK CMD_FAIL ok_status fail_status "$PAIR_TMPDIR/syntax-ok" "$PAIR_TMPDIR/syntax-fail"

  if [ "$ok_status" -eq 0 ]; then report "ok-playbook (유효한 문법)" 0; else report "ok-playbook (유효한 문법)" 1 "기대 exit=0 / 실제 exit=$ok_status"; fi
  if [ "$fail_status" -ne 0 ]; then report "fail-syntax-playbook (문법 오류 차단)" 0; else report "fail-syntax-playbook (문법 오류 차단)" 1 "기대 exit≠0 / 실제 exit=$fail_status"; fi
fi

echo "--- ansible-lint ---"
if require_tool ansible-lint; then
  # ansible-lint는 인자 없이 현재 디렉토리를 스캔하므로 cd가 선행돼야 한다 -> bash -c로 묶는다.
  # shellcheck disable=SC2034,SC2016 # nameref로 간접 참조됨 / $1은 bash -c 서브셸 안에서 확장돼야 함
  CMD_OK=(bash -c 'cd "$1" && ansible-lint' _ "$FIXTURES/lint-ok")
  # shellcheck disable=SC2034,SC2016
  CMD_FAIL=(bash -c 'cd "$1" && ansible-lint' _ "$FIXTURES/lint-fail")
  ok_status=0
  fail_status=0
  parallel_pair_run CMD_OK CMD_FAIL ok_status fail_status "$PAIR_TMPDIR/lint-ok" "$PAIR_TMPDIR/lint-fail"

  if [ "$ok_status" -eq 0 ]; then report "lint-ok (지적 0건)" 0; else report "lint-ok (지적 0건)" 1 "기대 exit=0 / 실제 exit=$ok_status"; fi

  if [ "$fail_status" -ne 0 ] && grep -qF "name[missing]" "$PAIR_TMPDIR/lint-fail"; then
    report "lint-fail (name[missing] 규칙 위반 차단)" 0
  else
    report "lint-fail (name[missing] 규칙 위반 차단)" 1 "기대 exit≠0 + name[missing] 문구 / 실제 exit=$fail_status"
  fi
fi

rm -rf "$PAIR_TMPDIR"

echo "--- validate_ansible (pre-flight-check.sh, 외부 저장소 배선) ---"
# 위 두 섹션은 도구를 직접 불러 "판정이 맞는가"만 본다. 정작 pre-flight-check.sh 가
# ansible-lint 를 "어떻게 부르는가"는 덮이지 않아, 설정 파일 경로를 무조건 넘기는
# 결함이 그대로 살아 있었다 — ansible/ansible-lint.yml 은 이 저장소 고유 배치인데
# -c 로 항상 지정해서, 그 파일이 없는 임의 저장소에서는 ansible-lint 가
# "Config file not found" 로 죽고 그 종료 코드가 "지적 사항 발견"으로 보고돼 무관한
# 커밋이 영구 차단됐다(실측: playbook.yml 하나뿐인 저장소에서 재현). 이 검증기는 전역
# core.hooksPath 훅이라 ~/workspace 하위 모든 저장소가 그 오탐을 그대로 맞는다.
#
# 두 케이스를 같이 둔다. 통과 케이스만 두면 "-c 를 떼는" 대신 "ansible-lint 자체를
# 건너뛰게" 만드는 회귀도 통과해 버리기 때문에, 설정 파일 없이도 실제로 린트가
# 도는지를 차단 케이스로 함께 고정한다.
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
PFC="$REPO_ROOT/bin/hooks/pre-flight-check.sh"
if [ -f "$PFC" ] && require_tool ansible-lint; then
  ANS_TMP=$(mktemp -d)

  new_ansible_repo() {
    local root=$1 src=$2
    mkdir -p "$root"
    git -C "$root" init -q
    git -C "$root" config user.email test@example.com
    git -C "$root" config user.name Test
    cp "$src" "$root/playbook.yml"
    git -C "$root" add playbook.yml
  }

  # Case 1: ansible/ansible-lint.yml 이 없는 저장소 — 지적 없는 플레이북은 통과해야 한다.
  AR1="$ANS_TMP/repo-ok"
  new_ansible_repo "$AR1" "$FIXTURES/lint-ok/playbook.yml"
  status=0
  out=$( (cd "$AR1" && QUIET=0 bash "$PFC") 2>&1) || status=$?
  if [ "$status" -eq 0 ]; then
    report "foreign-repo-no-config (설정 파일 없는 저장소 -> 오탐 차단 없음)" 0
  else
    report "foreign-repo-no-config (설정 파일 없는 저장소 -> 오탐 차단 없음)" 1 "기대 exit=0 / 실제 exit=$status out=$out"
  fi

  # Case 2: 같은 조건에서 실제 위반은 여전히 잡아야 한다(린트가 살아 있음을 증명).
  AR2="$ANS_TMP/repo-fail"
  new_ansible_repo "$AR2" "$FIXTURES/lint-fail/playbook.yml"
  status=0
  out=$( (cd "$AR2" && QUIET=0 bash "$PFC") 2>&1) || status=$?
  if [ "$status" -ne 0 ] && grep -qF "ansible-lint 지적 사항이 발견되어" <<<"$out"; then
    report "foreign-repo-no-config-still-lints (설정 파일 없어도 실제 위반은 차단)" 0
  else
    report "foreign-repo-no-config-still-lints (설정 파일 없어도 실제 위반은 차단)" 1 "기대 exit≠0 + ansible-lint 문구 / 실제 exit=$status out=$out"
  fi

  rm -rf "$ANS_TMP"
fi

echo "--- play-level privilege PATH isolation ---"
# play-level environment는 role의 become:true 태스크에도 상속된다. HOME 아래의 user-writable
# mise shims/~/.local/bin을 전역 PATH 앞에 두면 root 태스크가 gpg/awk 같은 bare command를
# 실행할 때 사용자가 심은 동명 바이너리를 집어올 수 있다. 권한 상승 태스크와 사용자
# toolchain PATH의 경계를 play 공통 계층에서 강제한다.
SITE_YML="$REPO_ROOT/ansible/site.yml"
if awk '
  /^  environment:$/ { in_env = 1; next }
  in_env && /^  [^[:space:]][^:]*:/ { in_env = 0 }
  in_env && /ansible_env\.HOME/ && /(mise\/shims|\.local\/bin)/ { bad = 1 }
  END { exit(bad ? 0 : 1) }
' "$SITE_YML"; then
  report "play-level PATH에 HOME 하위 user-writable 경로 금지" 1 "site.yml의 전역 environment PATH가 become:true 태스크에도 상속됩니다"
else
  report "play-level PATH에 HOME 하위 user-writable 경로 금지" 0
fi

# 전역 PATH를 제거해도 mise로 설치한 tflint 탐지는 유지되어야 한다. HOME toolchain PATH는
# become을 쓰지 않는 tflint task에만 국소화한다.
TFLINT_TASKS="$REPO_ROOT/ansible/roles/tflint/tasks/main.yml"
if grep -Fq 'PATH: "{{ ansible_env.HOME }}/.local/share/mise/shims:{{ ansible_env.PATH }}"' "$TFLINT_TASKS"; then
  report "mise PATH는 non-privileged tflint 태스크에 국소화" 0
else
  report "mise PATH는 non-privileged tflint 태스크에 국소화" 1 "tflint 탐지/초기화용 PATH가 사라졌습니다"
fi

echo "--- RHEL EPEL bootstrap contract ---"
PACKAGES_TASKS="$REPO_ROOT/ansible/roles/packages/tasks/main.yml"
if grep -Fq 'epel-release-latest-{{ ansible_distribution_major_version }}.noarch.rpm' "$PACKAGES_TASKS" &&
  ! grep -Eq '^[[:space:]]+name:[[:space:]]+epel-release([[:space:]]|$)' "$PACKAGES_TASKS"; then
  report "RHEL packages role은 메이저 버전별 EPEL release RPM을 직접 bootstrap" 0
else
  report "RHEL packages role은 메이저 버전별 EPEL release RPM을 직접 bootstrap" 1 "stock RHEL 기본 저장소에는 epel-release가 없을 수 있으므로 bare package명에 의존하면 안 됩니다"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
