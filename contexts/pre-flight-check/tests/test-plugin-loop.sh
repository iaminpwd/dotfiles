#!/usr/bin/env bash
# test-plugin-loop.sh
#
# run_delegated_skill_checks() 가 첫 플러그인 실패에서 즉시 중단하면 뒤 플러그인은
# 실행조차 안 된다. PrometheusRule YAML은 k8s-check.sh(PromQL 문법)와
# observability-check.sh(알람 정책) 양쪽의 대상이라, 파일 하나가 두 플러그인을
# 동시에 위반할 수 있다. 글롭이 알파벳 순으로 k8s-check.sh 를 먼저 도니, fail-fast
# 구조라면 observability-check.sh 의 위반이 재커밋 전까지 드러나지 않는다. 두
# 플러그인이 실제로 둘 다 끝까지 실행되고 둘 다 보고하는지 고정한다.
#
# 사용: bash ~/dotfiles/contexts/pre-flight-check/tests/test-plugin-loop.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

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

echo "--- 플러그인 루프 exhaustive 판정 ---"

if command -v yq >/dev/null 2>&1 && command -v promtool >/dev/null 2>&1; then
  PLUGIN_REPO="$TMP/plugin-loop"
  mkdir -p "$PLUGIN_REPO"
  git -C "$PLUGIN_REPO" init -q
  cat >"$PLUGIN_REPO/both-plugins-fail.yaml" <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: fail-both-plugins
  namespace: sample
spec:
  groups:
    - name: sample.rules
      rules:
        - alert: BrokenAndUnrunbooked
          expr: rate(http_requests_total[5m] > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: PromQL 문법 오류 + runbook_url 누락 동시 재현
EOF
  git -C "$PLUGIN_REPO" add both-plugins-fail.yaml
  CODE=0
  OUT=$( (cd "$PLUGIN_REPO" && QUIET=0 bash "$REPO_ROOT/bin/hooks/pre-flight-check.sh") 2>&1) || CODE=$?
  if [ "$CODE" -eq 1 ] && grep -qF "PromQL Alerting Rule 문법 검증에 실패" <<<"$OUT" && grep -qF "알람 정책" <<<"$OUT"; then
    report "플러그인 루프가 두 위반 모두 보고" 0
  else
    report "플러그인 루프가 두 위반 모두 보고" 1 "exit=$CODE / k8s 문구 감지=$(grep -qF 'PromQL Alerting Rule 문법 검증에 실패' <<<"$OUT" && echo yes || echo no), observability 문구 감지=$(grep -qF '알람 정책' <<<"$OUT" && echo yes || echo no)"
  fi
else
  report "플러그인 루프가 두 위반 모두 보고" 1 "도구 미설치: yq 또는 promtool — 'mise install' 후 다시 실행하십시오"
fi

# -----------------------------------------------------------------------------
# main() 배선 정적 검사
# -----------------------------------------------------------------------------
# 위 케이스는 run_delegated_skill_checks 의 "루프가 끝까지 도는가"를 본다. 그런데 그 함수든
# validate_* 든 main() 호출 목록에서 빠지면 루프고 뭐고 애초에 실행되지 않는다.
#
# 이 축이 지금까지 비어 있었다는 것을 실측으로 확인했다: validate_terraform /
# validate_docker / validate_k8s_manifests 를 각각 통째로 `return 0` 으로 바꿔도
# aws / containers / k8s 스킬 스위트가 전부 통과했다. 그 스위트들이 pre-flight-check 를
# 경유하지 않고 terraform/hadolint/kube-linter 를 직접 재현하기 때문이다.
#
# 행동으로 재현하려면 검증기별 위반 픽스처를 만들어 pre-flight-check 를 실제로 돌려야 하는데,
# 실측상 위반 .tf 하나로 전체 파이프라인이 14.6초가 걸리고 fail-fast 라 첫 실패 게이트
# 하나만 확인된다(12개 중 1개). 그 비용으로 얻는 것이 "배선이 살아 있다"뿐이라면 정적
# 대조가 같은 것을 1ms 에 준다 — test-pre-flight-live-hook.sh 가 $HOME 하드코딩을
# 같은 근거로 정적 검사한 선례를 따른다.
#
# 이 검사가 못 잡는 것: 함수는 배선돼 있는데 내부 판정이 망가진 경우. 그쪽은 스킬 스위트의
# 도구 룰 ID 계약 검사와 test-shell/test-yaml 의 실제 호출 케이스가 담당한다.
PFC="$REPO_ROOT/bin/hooks/pre-flight-check.sh"
MAIN_BODY=$(sed -n '/^main() {/,/^}/p' "$PFC")
MISSING=()
while IFS= read -r fn; do
  [ -n "$fn" ] || continue
  grep -qE "^[[:space:]]+${fn}([[:space:]]|$)" <<<"$MAIN_BODY" || MISSING+=("$fn")
done < <(grep -hoE '^(validate_[a-z_]+|run_delegated_skill_checks)\(\) \{' "$PFC" "$REPO_ROOT"/bin/lib/pfc-*.sh 2>/dev/null | sed 's/() {//' | sort -u)

if [ "${#MISSING[@]}" -eq 0 ]; then
  report "main() 배선 (정의된 검증 함수가 전부 호출됨)" 0
else
  report "main() 배선 (정의된 검증 함수가 전부 호출됨)" 1 "main() 에서 빠진 함수: ${MISSING[*]}"
fi

# -----------------------------------------------------------------------------
# 검증기별 실제 호출 스모크 (배선 정적 검사가 못 잡는 "본문 훼손" 축)
# -----------------------------------------------------------------------------
# 위 정적 검사는 "호출이 main() 에 있는가"만 본다. 함수는 배선돼 있는데 본문이 통째로
# return 0 이 되면 잡지 못한다. validate_shell / validate_yaml 은 test-shell.sh /
# test-yaml.sh 가 pre-flight-check 를 실제로 호출해 그 축을 이미 덮고 있는데,
# terraform / docker / k8s 만 비어 있었다(실측: 셋 다 무력화해도 스킬 스위트 전원 통과).
#
# 비싸지 않다. 검증기는 대상 파일이 없으면 통째로 건너뛰므로, Dockerfile 만 있는 저장소는
# terraform 계열을 아예 안 탄다. terraform 도 validate_terraform 이 fmt 에서 fail-fast 라
# 포맷만 어긴 .tf 면 init/tflint/checkov 까지 가지 않는다(실측 0.1초 / 0.0초 / 0.0초).
# 반대로 포맷이 맞는데 checkov 만 어기는 픽스처를 쓰면 전체 파이프라인이 돌아 14.6초가 된다 —
# "첫 하위 게이트를 어긴다"가 이 스모크를 싸게 유지하는 조건이므로 픽스처를 바꿀 때 주의할 것.
#
# 각 게이트의 판정 정확도까지 여기서 보지는 않는다. 그건 스킬 스위트의 도구 룰 ID 계약
# 검사가 담당한다. 여기서 고정하는 것은 "그 검증기가 실제로 실행되어 커밋을 막는가" 하나다.
smoke_repo() {
  local dir=$1
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name Test
}

run_smoke() {
  local name=$1 dir=$2 want_text=$3 code=0 out
  out=$( (cd "$dir" && QUIET=0 bash "$REPO_ROOT/bin/hooks/pre-flight-check.sh") 2>&1) || code=$?
  if [ "$code" -ne 0 ] && grep -qF "$want_text" <<<"$out"; then
    report "$name" 0
  else
    report "$name" 1 "기대 exit≠0 + '$want_text' / 실제 exit=$code: $(grep -m1 '❌' <<<"$out")"
  fi
}

SMOKE_TF="$TMP/smoke-tf"
smoke_repo "$SMOKE_TF"
# 들여쓰기 4칸 = terraform fmt 위반(validate_terraform 의 첫 하위 게이트).
printf 'resource "aws_s3_bucket" "b" {\n    bucket = "x"\n}\n' >"$SMOKE_TF/main.tf"
git -C "$SMOKE_TF" add main.tf
run_smoke "validate_terraform 실제 호출 (커밋 차단)" "$SMOKE_TF" "terraform fmt 포맷이 맞지 않아"

SMOKE_DOCKER="$TMP/smoke-docker"
smoke_repo "$SMOKE_DOCKER"
printf 'FROM ubuntu\nRUN apt-get install -y curl\n' >"$SMOKE_DOCKER/Dockerfile"
git -C "$SMOKE_DOCKER" add Dockerfile
run_smoke "validate_docker 실제 호출 (커밋 차단)" "$SMOKE_DOCKER" "hadolint 지적 사항"

SMOKE_K8S="$TMP/smoke-k8s"
smoke_repo "$SMOKE_K8S"
cat >"$SMOKE_K8S/pod.yaml" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: p
spec:
  containers:
    - name: c
      image: nginx
      securityContext:
        privileged: true
EOF
git -C "$SMOKE_K8S" add pod.yaml
run_smoke "validate_k8s_manifests 실제 호출 (커밋 차단)" "$SMOKE_K8S" "kube-linter 지적 사항"

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
