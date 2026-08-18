#!/usr/bin/env bash
# k8s 검증 파이프라인 회귀 테스트
#
# 각 픽스처는 010-k8s-core.md 의 특정 조항이나 중단 조건을 재현한다. 목적은
# pre-flight-check.sh / k8s-check.sh 가 호출하는 검증기를 손볼 때, 기존 검사가
# 조용히 죽어서 위반 매니페스트가 통과되는 상황을 제어하는 것이다.
#
# 검증기가 스테이징된 파일을 대상으로 동작하는 것과 달리 이 러너는 픽스처를
# 직접 넘긴다. 대신 검증기가 쓰는 것과 동일한 명령·옵션을 그대로 사용해,
# 파이프라인이 실제로 잡는 것만 잡는다고 주장하도록 맞췄다.
#
# 사용: bash ~/dotfiles/contexts/k8s/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
FIXTURES="$TESTS_DIR/fixtures"
KYVERNO_FIXTURES="$TESTS_DIR/fixtures-kyverno"

PASS_COUNT=0
FAIL_COUNT=0
CHECKED=()

# 도구 미설치는 SKIP 이 아니라 실패로 처리한다. 조용히 건너뛰면 회귀 테스트가
# 통과했다는 신호만 남기고 실제로는 아무것도 검증하지 않는다.
require_tool() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "  FAIL  도구 미설치: $1 — 'mise install $1' 후 다시 실행하십시오"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  return 1
}

report() {
  local name=$1 ok=$2 detail=${3:-}
  CHECKED+=("$name")
  if [ "$ok" -eq 0 ]; then
    echo "  PASS  $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL  $name"
    [ -n "$detail" ] && echo "        $detail"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# pre-flight-check.sh 의 validate_k8s_manifests 와 동일하게 'kube-linter lint <file>' 를 호출한다.
# want_check 가 빈 문자열이면 지적 0건을 기대한다.
run_kube_linter() {
  local name=$1 want_check=${2:-}
  local out status
  out=$(kube-linter lint "$FIXTURES/$name" 2>&1) && status=0 || status=$?

  if [ -z "$want_check" ]; then
    if [ "$status" -eq 0 ]; then
      report "$name" 0
    else
      report "$name" 1 "기대: 지적 0건 / 실제: $(grep -oE '\(check: [a-z-]+' <<<"$out" | sed 's/(check: //' | sort -u | tr '\n' ' ')"
    fi
    return
  fi

  if [ "$status" -ne 0 ] && grep -q "(check: $want_check" <<<"$out"; then
    report "$name" 0
  else
    report "$name" 1 "기대: '$want_check' 지적 / 실제 exit=$status, checks=$(grep -oE '\(check: [a-z-]+' <<<"$out" | sed 's/(check: //' | sort -u | tr '\n' ' ')"
  fi
}

# k8s-check.sh 의 check_prometheus_rules 와 동일하게 yq 로 .spec 을 벗겨 promtool 에 넘긴다.
run_promtool() {
  local name=$1 want_fail=$2
  local tmp out status
  tmp=$(mktemp)
  yq eval '.spec' "$FIXTURES/$name" >"$tmp"
  out=$(promtool check rules "$tmp" 2>&1) && status=0 || status=$?
  rm -f "$tmp"

  if [ "$want_fail" -eq 1 ] && [ "$status" -ne 0 ]; then
    report "$name" 0
  elif [ "$want_fail" -eq 0 ] && [ "$status" -eq 0 ]; then
    report "$name" 0
  else
    report "$name" 1 "기대: $([ "$want_fail" -eq 1 ] && echo '문법 오류 검출' || echo '통과') / 실제 exit=$status: $(echo "$out" | tail -1)"
  fi
}

# k8s-check.sh 의 check_deprecated_apis 와 동일하게 'pluto detect-files -d <dir>' 를 호출한다.
# pluto 는 디렉토리 단위로 스캔하므로 픽스처마다 격리된 임시 디렉토리를 쓴다.
run_pluto() {
  local name=$1 want_fail=$2
  local dir out status
  dir=$(mktemp -d)
  cp "$FIXTURES/$name" "$dir/"
  out=$(pluto detect-files -d "$dir" 2>&1) && status=0 || status=$?
  rm -rf "$dir"

  if [ "$want_fail" -eq 1 ] && [ "$status" -ne 0 ]; then
    report "$name" 0
  elif [ "$want_fail" -eq 0 ] && [ "$status" -eq 0 ]; then
    report "$name" 0
  else
    report "$name" 1 "기대: $([ "$want_fail" -eq 1 ] && echo 'deprecated API 검출' || echo '통과') / 실제 exit=$status: $(echo "$out" | tail -1)"
  fi
}

echo "=== k8s 검증 파이프라인 회귀 테스트 ==="

# 이 섹션이 실제로 지키는 것은 "kube-linter 가 우리가 의존하는 체크 이름을 여전히 낸다"는
# 도구 의존 계약이다(우리 코드는 경유하지 않는다). Renovate 가 mise 도구 버전을 매주 자동으로
# 올리므로 그 계약은 실제로 흔들리고, 깨지면 pre-flight 게이트가 조용히 아무것도 막지 않는다.
# 대표 체크 하나만 남긴다 — 도구가 체크 셋을 개편하면 여러 개가 같이 바뀌지 하나만 바뀌지
# 않으므로 개수를 늘려도 잡히는 사건은 같고 픽스처 관리 비용만 는다.
# (host-network / run-as-non-root / unset-memory-requirements 케이스와 픽스처는 이 근거로 제거.)
echo "--- kube-linter (pre-flight-check.sh) ---"
if require_tool kube-linter; then
  run_kube_linter ok-baseline.yaml ""
  run_kube_linter fail-privileged.yaml privileged-container
fi

echo "--- promtool (k8s-check.sh) ---"
if require_tool promtool && require_tool yq; then
  run_promtool ok-prometheus-rule.yaml 0
  run_promtool fail-promql-syntax.yaml 1
fi

echo "--- pluto (k8s-check.sh) ---"
if require_tool pluto; then
  run_pluto ok-baseline.yaml 0
  run_pluto fail-deprecated-api.yaml 1
fi

echo "--- kyverno test (k8s-check.sh) ---"
# kube-linter의 fail-privileged.yaml과 동일한 관심사(privileged 컨테이너 금지)를
# Kyverno 네이티브 정책으로도 표현한 픽스처. kyverno test는 helm/conftest처럼
# 디렉토리 단위로 동작하며, "리소스가 위반하는가"가 아니라 "선언한 기대 결과가
# 실제 판정과 일치하는가"를 검사한다는 점이 다른 도구들과 다르다. 그래서
# fail-broken-expectation은 위반 리소스가 있다는 뜻이 아니라, 기대 결과 자체가
# 실제 판정과 어긋난다는 뜻이다 — 정책이 규정과 다르게 바뀌었거나 테스트
# 기대값이 낡았을 때와 같은 신호다.
if require_tool kyverno; then
  status=0
  kyverno test "$KYVERNO_FIXTURES/ok-baseline" >/dev/null 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then
    report "ok-baseline (기대 결과가 실제 판정과 일치)" 0
  else
    report "ok-baseline (기대 결과가 실제 판정과 일치)" 1 "기대 exit=0 / 실제 exit=$status"
  fi

  status=0
  out=$(kyverno test "$KYVERNO_FIXTURES/fail-broken-expectation" 2>&1) || status=$?
  if [ "$status" -ne 0 ] && grep -qF "tests failed" <<<"$out"; then
    report "fail-broken-expectation (기대 결과 불일치 검출)" 0
  else
    report "fail-broken-expectation (기대 결과 불일치 검출)" 1 "기대 exit≠0 + 'tests failed' 문구 / 실제 exit=$status"
  fi
fi

echo "--- k8s-check.sh (bin/hooks/plugins, 커밋 시점 배선) ---"
# 위 promtool/pluto 섹션은 "판정 로직이 맞는가"만 본다. k8s-check.sh 자신의
# 오케스트레이션(스테이징된 yaml 중 어떤 kind:가 어떤 서브체크를 트리거하는지,
# 격리 tmpdir로 pluto 스캔 범위를 좁히는지)은 여기서 격리 저장소를 만들어
# 실제 호출까지 검증한다(aiops-check.sh/observability-check.sh와 동일 패턴).
K8S_PLUGIN="$REPO_ROOT/bin/hooks/plugins/k8s-check.sh"
if [ -x "$K8S_PLUGIN" ]; then
  PLUGIN_TMP=$(mktemp -d)

  run_plugin() {
    local repo=$1 status=0
    (cd "$repo" && QUIET=0 bash "$K8S_PLUGIN") >"$PLUGIN_TMP/out" 2>&1 || status=$?
    echo "$status"
  }

  new_plugin_repo() {
    local root=$1
    mkdir -p "$root"
    git -C "$root" init -q
    git -C "$root" config user.email test@example.com
    git -C "$root" config user.name Test
  }

  if require_tool promtool && require_tool yq; then
    # Case 1: kind: PrometheusRule + PromQL 문법 오류 -> 커밋 차단.
    KR1="$PLUGIN_TMP/repo1"
    new_plugin_repo "$KR1"
    cp "$FIXTURES/fail-promql-syntax.yaml" "$KR1/rule.yaml"
    git -C "$KR1" add rule.yaml
    status=$(run_plugin "$KR1")
    if [ "$status" -eq 1 ] && grep -qF "PromQL Alerting Rule 문법 검증" "$PLUGIN_TMP/out"; then
      report "prometheus-trigger-and-block (PromQL 문법 오류 -> 차단)" 0
    else
      report "prometheus-trigger-and-block (PromQL 문법 오류 -> 차단)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi

    # Case 2: kind: PrometheusRule + 문법 정상 -> 통과.
    KR2="$PLUGIN_TMP/repo2"
    new_plugin_repo "$KR2"
    cp "$FIXTURES/ok-prometheus-rule.yaml" "$KR2/rule.yaml"
    git -C "$KR2" add rule.yaml
    status=$(run_plugin "$KR2")
    if [ "$status" -eq 0 ]; then
      report "prometheus-trigger-and-pass (PromQL 정상 -> 통과)" 0
    else
      report "prometheus-trigger-and-pass (PromQL 정상 -> 통과)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi

    # Case 2b~2c: 멀티 도큐먼트 매니페스트에서도 게이트가 살아 있어야 한다.
    #
    # 예전엔 파일 전체에 `yq eval '.spec'` 을 걸었다. PrometheusRule 이 아닌 문서는
    # .spec 이 null 로 나오고, 그 null 이 출력의 첫 문서가 되면 promtool 이 "Multiple
    # document yaml rules files are not supported, only the first document is processed"
    # 를 경고하며 null 만 보고 "0 rules found / SUCCESS" 로 끝났다. 실측: 같은 깨진
    # PromQL 이 단독 파일이면 exit 1, 앞에 ConfigMap 문서 하나만 붙이면 exit 0.
    # K8s 에서 멀티 도큐먼트는 아주 흔하므로 게이트가 사실상 우회 가능했다.
    KR2B="$PLUGIN_TMP/repo2b"
    new_plugin_repo "$KR2B"
    {
      printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: cm\ndata:\n  a: b\n---\n'
      cat "$FIXTURES/fail-promql-syntax.yaml"
    } >"$KR2B/rule.yaml"
    git -C "$KR2B" add rule.yaml
    status=$(run_plugin "$KR2B")
    if [ "$status" -eq 1 ] && grep -qF "PromQL Alerting Rule 문법 검증" "$PLUGIN_TMP/out"; then
      report "prometheus-multidoc-block (앞 문서에 가려도 차단)" 0
    else
      report "prometheus-multidoc-block (앞 문서에 가려도 차단)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi

    # 두 번째 PrometheusRule 문서만 깨진 경우. 문서별로 돌지 않으면 첫 개만 보고 통과한다.
    KR2C="$PLUGIN_TMP/repo2c"
    new_plugin_repo "$KR2C"
    {
      cat "$FIXTURES/ok-prometheus-rule.yaml"
      printf -- '---\n'
      cat "$FIXTURES/fail-promql-syntax.yaml"
    } >"$KR2C/rule.yaml"
    git -C "$KR2C" add rule.yaml
    status=$(run_plugin "$KR2C")
    if [ "$status" -eq 1 ] && grep -qF "PromQL Alerting Rule 문법 검증" "$PLUGIN_TMP/out"; then
      report "prometheus-multidoc-second-rule (뒤 문서 위반도 차단)" 0
    else
      report "prometheus-multidoc-second-rule (뒤 문서 위반도 차단)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi

    # 오탐 회귀: 정상 Rule 이 다른 문서와 함께 있어도 통과해야 한다.
    KR2D="$PLUGIN_TMP/repo2d"
    new_plugin_repo "$KR2D"
    {
      printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: cm\ndata:\n  a: b\n---\n'
      cat "$FIXTURES/ok-prometheus-rule.yaml"
    } >"$KR2D/rule.yaml"
    git -C "$KR2D" add rule.yaml
    status=$(run_plugin "$KR2D")
    if [ "$status" -eq 0 ]; then
      report "prometheus-multidoc-pass (정상 Rule 은 오탐 없음)" 0
    else
      report "prometheus-multidoc-pass (정상 Rule 은 오탐 없음)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi
  fi

  if require_tool pluto; then
    # Case 3: 삭제된 API 버전 -> 커밋 차단(격리 tmpdir로 pluto -d 스캔 범위가
    # 스테이징된 파일로만 좁혀지는지까지 함께 확인).
    KR3="$PLUGIN_TMP/repo3"
    new_plugin_repo "$KR3"
    cp "$FIXTURES/fail-deprecated-api.yaml" "$KR3/ingress.yaml"
    git -C "$KR3" add ingress.yaml
    status=$(run_plugin "$KR3")
    if [ "$status" -eq 1 ] && grep -qF "삭제 예정" "$PLUGIN_TMP/out"; then
      report "deprecated-api-trigger-and-block (제거된 API -> 차단)" 0
    else
      report "deprecated-api-trigger-and-block (제거된 API -> 차단)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi

    # Case 4: 정상 매니페스트(kind: 있음, 삭제된 API 아님) -> 통과.
    KR4="$PLUGIN_TMP/repo4"
    new_plugin_repo "$KR4"
    cp "$FIXTURES/ok-baseline.yaml" "$KR4/deploy.yaml"
    git -C "$KR4" add deploy.yaml
    status=$(run_plugin "$KR4")
    if [ "$status" -eq 0 ]; then
      report "deprecated-api-trigger-and-pass (정상 매니페스트 -> 통과)" 0
    else
      report "deprecated-api-trigger-and-pass (정상 매니페스트 -> 통과)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi
  fi

  # Case 5: kind: 필드 자체가 없는 순수 데이터 yaml -> 어떤 서브체크도 트리거 안 됨.
  KR5="$PLUGIN_TMP/repo5"
  new_plugin_repo "$KR5"
  cat >"$KR5/data.yaml" <<'EOF'
just: some data
without: a kind field
EOF
  git -C "$KR5" add data.yaml
  status=$(run_plugin "$KR5")
  if [ "$status" -eq 0 ]; then
    report "no-trigger-without-kind (kind: 없는 yaml은 무동작)" 0
  else
    report "no-trigger-without-kind (kind: 없는 yaml은 무동작)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
  fi

  if require_tool kyverno; then
    # Case 6: *kyverno-test.yaml 이 스테이징되면 그 디렉토리에서 kyverno test를
    # 실제로 실행한다. check_kyverno는 파일 하나가 아니라 kyverno-test.yaml이
    # 위치한 디렉토리 전체(policy.yaml/resources.yaml 포함)를 대상으로 하므로
    # 세 파일을 함께 배치한다.
    KR6="$PLUGIN_TMP/repo6"
    new_plugin_repo "$KR6"
    cp "$KYVERNO_FIXTURES/fail-broken-expectation/policy.yaml" "$KR6/policy.yaml"
    cp "$KYVERNO_FIXTURES/fail-broken-expectation/resources.yaml" "$KR6/resources.yaml"
    cp "$KYVERNO_FIXTURES/fail-broken-expectation/kyverno-test.yaml" "$KR6/kyverno-test.yaml"
    git -C "$KR6" add policy.yaml resources.yaml kyverno-test.yaml
    status=$(run_plugin "$KR6")
    if [ "$status" -eq 1 ] && grep -qF "Kyverno 정책 테스트가 실패" "$PLUGIN_TMP/out"; then
      report "kyverno-trigger-and-block (기대 결과 불일치 -> 차단)" 0
    else
      report "kyverno-trigger-and-block (기대 결과 불일치 -> 차단)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi

    KR7="$PLUGIN_TMP/repo7"
    new_plugin_repo "$KR7"
    cp "$KYVERNO_FIXTURES/ok-baseline/policy.yaml" "$KR7/policy.yaml"
    cp "$KYVERNO_FIXTURES/ok-baseline/resources.yaml" "$KR7/resources.yaml"
    cp "$KYVERNO_FIXTURES/ok-baseline/kyverno-test.yaml" "$KR7/kyverno-test.yaml"
    git -C "$KR7" add policy.yaml resources.yaml kyverno-test.yaml
    status=$(run_plugin "$KR7")
    if [ "$status" -eq 0 ]; then
      report "kyverno-trigger-and-pass (기대 결과 일치 -> 통과)" 0
    else
      report "kyverno-trigger-and-pass (기대 결과 일치 -> 통과)" 1 "exit=$status out=$(cat "$PLUGIN_TMP/out")"
    fi
  fi

  rm -rf "$PLUGIN_TMP"
else
  report "k8s-check.sh 플러그인 배선 확인" 1 "bin/hooks/plugins/k8s-check.sh 를 찾을 수 없거나 실행 권한이 없습니다"
fi

# validate_helm/validate_conftest(pre-flight-check.sh)는 다른 픽스처처럼 단일 yaml
# 파일이 아니라 차트 디렉토리/정책 디렉토리 단위라 fixtures-helm/, fixtures-conftest/
# 로 따로 둔다.
echo "--- helm lint (pre-flight-check.sh) ---"
if require_tool helm; then
  HELM_FIXTURES="$TESTS_DIR/fixtures-helm"
  status=0
  helm lint "$HELM_FIXTURES/ok-chart" >/dev/null 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then report "ok-chart (유효한 차트)" 0; else report "ok-chart (유효한 차트)" 1 "기대 exit=0 / 실제 exit=$status"; fi

  status=0
  out=$(helm lint "$HELM_FIXTURES/fail-chart" 2>&1) || status=$?
  if [ "$status" -ne 0 ] && grep -qF "parse error" <<<"$out"; then
    report "fail-chart (템플릿 파싱 오류 차단)" 0
  else
    report "fail-chart (템플릿 파싱 오류 차단)" 1 "기대 exit≠0 + parse error / 실제 exit=$status"
  fi

  # 위 두 케이스는 helm lint 를 직접 불러 "판정이 맞는가"만 본다. 정작 validate_helm 이
  # 검사할 차트 디렉토리를 "찾아내는" 단계는 덮이지 않아, 루트에 놓인 차트가 한 번도
  # lint 되지 않는 결함이 그대로 살아 있었다 — dirname 이 "." 이라 비교 대상이
  # "./Chart.yaml"/"./*" 가 되는데 git 이 주는 경로엔 그 접두사가 없어 매칭이 전부
  # 빗나갔다(실측: 같은 차트를 sub/ 로 옮기면 검출, 루트에 두면 미검출). 차트 저장소는
  # 루트에 Chart.yaml 을 두는 배치가 가장 흔하므로 그 경로를 격리 저장소로 고정한다.
  PFC="$REPO_ROOT/bin/hooks/pre-flight-check.sh"
  if [ -f "$PFC" ]; then
    HELM_TMP=$(mktemp -d)
    cp -r "$HELM_FIXTURES/fail-chart/." "$HELM_TMP/"
    git -C "$HELM_TMP" init -q
    git -C "$HELM_TMP" config user.email test@example.com
    git -C "$HELM_TMP" config user.name Test
    git -C "$HELM_TMP" add -A

    status=0
    out=$( (cd "$HELM_TMP" && QUIET=0 bash "$PFC") 2>&1) || status=$?
    if [ "$status" -ne 0 ] && grep -qF "Helm lint" <<<"$out"; then
      report "root-chart-is-linted (루트 배치 차트도 helm lint 대상)" 0
    else
      report "root-chart-is-linted (루트 배치 차트도 helm lint 대상)" 1 "기대 exit≠0 + Helm lint / 실제 exit=$status out=$out"
    fi

    rm -rf "$HELM_TMP"

    # 위 케이스는 staged 모드만 본다. 같은 차트를 explicit 모드(파일 경로 지정)로 넘기면
    # 대상 목록이 절대경로가 되는데(pre-flight-check.sh 의 parse_target_args), validate_helm
    # 의 차트 디렉토리 판정은 git ls-files 가 주는 상대경로와 접두사를 맞춰 보는 구조라
    # 매치가 전부 빗나가 helm lint 가 한 번도 돌지 않은 채 exit 0 이 났다(실측: 같은 차트가
    # staged 에서는 차단, explicit 에서는 "Step: Helm Chart Validation" 줄조차 없이 통과).
    # explicit 는 pre-flight-live-hook.sh 가 AI 편집 1회마다 쓰는 경로라, 편집 직후 피드백이
    # 통째로 비어 있으면서 초록불만 떴다. 두 모드의 판정이 같아야 함을 축으로 고정한다.
    #
    # 차트를 반드시 하위 디렉토리에 둔다. 루트 배치(바로 위 케이스)는 dirname 이 "." 라
    # 비교 접두사가 빈 문자열이 되어 어떤 절대경로와도 매치되므로, 이 결함이 구조적으로
    # 드러나지 않는다 — 루트 픽스처로 이 케이스를 쓰면 수정을 되돌려도 통과한다(실측).
    HELM_SUB_TMP=$(mktemp -d)
    mkdir -p "$HELM_SUB_TMP/charts/sample"
    cp -r "$HELM_FIXTURES/fail-chart/." "$HELM_SUB_TMP/charts/sample/"
    git -C "$HELM_SUB_TMP" init -q
    git -C "$HELM_SUB_TMP" config user.email test@example.com
    git -C "$HELM_SUB_TMP" config user.name Test
    git -C "$HELM_SUB_TMP" add -A

    status=0
    out=$( (cd "$HELM_SUB_TMP" && QUIET=0 bash "$PFC" "$HELM_SUB_TMP/charts/sample/Chart.yaml") 2>&1) || status=$?
    if [ "$status" -ne 0 ] && grep -qF "Helm lint" <<<"$out"; then
      report "explicit-mode-chart-is-linted (파일 지정 모드도 staged 와 동일 판정)" 0
    else
      report "explicit-mode-chart-is-linted (파일 지정 모드도 staged 와 동일 판정)" 1 "기대 exit≠0 + Helm lint / 실제 exit=$status out=$out"
    fi
    rm -rf "$HELM_SUB_TMP"
  fi
fi

echo "--- conftest (pre-flight-check.sh) ---"
if require_tool conftest; then
  CONFTEST_FIXTURES="$TESTS_DIR/fixtures-conftest"
  status=0
  conftest test --policy "$CONFTEST_FIXTURES/policy" "$CONFTEST_FIXTURES/ok-pod.yaml" >/dev/null 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then report "ok-pod (정책 위반 없음)" 0; else report "ok-pod (정책 위반 없음)" 1 "기대 exit=0 / 실제 exit=$status"; fi

  status=0
  out=$(conftest test --policy "$CONFTEST_FIXTURES/policy" "$CONFTEST_FIXTURES/fail-pod.yaml" 2>&1) || status=$?
  if [ "$status" -ne 0 ] && grep -qF "hostNetwork must not be true" <<<"$out"; then
    report "fail-pod (hostNetwork 정책 위반 차단)" 0
  else
    report "fail-pod (hostNetwork 정책 위반 차단)" 1 "기대 exit≠0 + 정책 위반 문구 / 실제 exit=$status"
  fi

  # 위 두 케이스는 conftest 를 직접 불러 "정책 판정이 맞는가"만 본다. 정작 validate_conftest
  # 가 정책 파일을 "어디서 모으는가"는 덮이지 않아, 픽스처 정책이 실검증 규칙으로 승격되는
  # 결함이 살아 있었다 — 정책 수집이 git ls-files 무필터라 */tests/fixtures* 하위의 정책이
  # --policy 로 실려 나갔다. 픽스처 정책은 "게이트가 실제로 차단하는가"를 확인하려고 일부러
  # 흔한 조건을 거부하도록 쓰는 것이라, 그대로 적용되면 무관한 커밋이 통째로 막힌다
  # (실측: tests/fixtures/policy/ 에 ConfigMap 을 거부하는 정책을 두자 평범한 ConfigMap
  # 커밋이 차단됐다. 이 저장소도 --all 실행 시 실제 YAML 62건이 fixtures-conftest 의
  # 정책으로 평가되고 있었다). 형제 검증기(checkov/trivy/db-sg-checker/filter_target_files)는
  # 전부 같은 제외를 갖고 있는데 conftest 만 빠져 있었다.
  #
  # 두 축을 함께 고정한다. 통과 케이스만 두면 "픽스처를 빼는" 대신 "conftest 를 아예 안
  # 도는" 회귀도 통과하므로, 픽스처 밖 정책은 여전히 차단하는지를 나란히 본다.
  PFC="$REPO_ROOT/bin/hooks/pre-flight-check.sh"
  if [ -f "$PFC" ]; then
    CONFTEST_TMP=$(mktemp -d)

    new_rego_repo() {
      local root=$1 policy_dir=$2
      mkdir -p "$root/$policy_dir"
      git -C "$root" init -q 2>/dev/null || { mkdir -p "$root" && git -C "$root" init -q; }
      git -C "$root" config user.email test@example.com
      git -C "$root" config user.name Test
      # 흔한 kind 를 무조건 거부하는 정책 — 픽스처가 실제로 그렇게 쓰인다.
      cat >"$root/$policy_dir/deny-configmap.rego" <<'REGO'
package main

deny contains msg if {
	input.kind == "ConfigMap"
	msg := "픽스처 전용 정책"
}
REGO
      cat >"$root/app.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: app
data:
  k: v
YAML
      git -C "$root" add -A
    }

    # Case 1: 정책이 픽스처 하위면 무시해야 한다(실검증 규칙으로 승격 금지).
    CR1="$CONFTEST_TMP/repo-fixture"
    new_rego_repo "$CR1" "tests/fixtures/policy"
    status=0
    out=$( (cd "$CR1" && QUIET=0 bash "$PFC") 2>&1) || status=$?
    if [ "$status" -eq 0 ]; then
      report "fixture-policy-excluded (픽스처 정책은 실검증에 쓰이지 않음)" 0
    else
      report "fixture-policy-excluded (픽스처 정책은 실검증에 쓰이지 않음)" 1 "기대 exit=0 / 실제 exit=$status out=$out"
    fi

    # Case 2: 같은 정책이 픽스처 밖이면 그대로 차단해야 한다(제외가 "정책을 봐주는 것"이
    # 아니라 "경로 때문"임을 증명).
    CR2="$CONFTEST_TMP/repo-real"
    new_rego_repo "$CR2" "policy"
    status=0
    out=$( (cd "$CR2" && QUIET=0 bash "$PFC") 2>&1) || status=$?
    if [ "$status" -ne 0 ] && grep -qF "Conftest 정책 위반" <<<"$out"; then
      report "real-policy-still-enforced (픽스처 밖 정책은 그대로 차단)" 0
    else
      report "real-policy-still-enforced (픽스처 밖 정책은 그대로 차단)" 1 "기대 exit≠0 + 정책 위반 문구 / 실제 exit=$status out=$out"
    fi

    rm -rf "$CONFTEST_TMP"
  fi
fi

# 기대 결과가 등록되지 않은 픽스처는 검증되지 않은 채 방치된다.
for path in "$FIXTURES"/*.yaml; do
  name=$(basename "$path")
  found=0
  for c in "${CHECKED[@]}"; do [ "$c" = "$name" ] && found=1 && break; done
  [ "$found" -eq 0 ] && echo "  WARN  $name — 기대 결과가 등록되지 않은 픽스처입니다"
done

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
