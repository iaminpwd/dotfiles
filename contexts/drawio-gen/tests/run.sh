#!/bin/bash
# drawio-gen 검증기 회귀 테스트
# 각 픽스처는 규칙이 만들어진 실제 실패 사례를 재현한다. layout_toolkit.validate() 를
# 수정할 때 기존 검사가 조용히 죽지 않는지 확인하는 것이 목적이다.
#
# 사용: bash ~/dotfiles/contexts/drawio-gen/tests/run.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TESTS_DIR/../scripts" && pwd)"

python3 - "$TESTS_DIR" "$SCRIPTS_DIR" <<'PY'
import sys, os, glob

tests_dir, scripts_dir = sys.argv[1], sys.argv[2]
sys.path.insert(0, scripts_dir)
from layout_toolkit import validate

# 픽스처별 기대 결과: (ok 여부, 리포트에 반드시 등장해야 할 문구)
EXPECTED = {
    "ok-baseline.drawio":            (True,  "[OK]"),
    "fail-duplicate-id.drawio":      (False, "[FAIL] 중복 ID"),
    "fail-broken-reference.drawio":  (False, "[FAIL] 끊어진 참조"),
    "fail-detached-edge.drawio":     (False, "[FAIL] 엣지 끝점 미연결"),
    "fail-palette-violation.drawio": (False, "[FAIL] 컨테이너 팔레트 위반"),
    "warn-sibling-overlap.drawio":   (True,  "[WARN] 형제 노드 겹침"),
    "warn-row-height.drawio":        (True,  "[WARN] 행 높이 불일치"),
    "warn-label-width.drawio":       (True,  "[WARN] 라벨 폭 초과 의심"),
}

fixtures = sorted(glob.glob(os.path.join(tests_dir, "fixtures", "*.drawio")))
names = {os.path.basename(p) for p in fixtures}

missing = sorted(set(EXPECTED) - names)
orphan = sorted(names - set(EXPECTED))
failed = []

print("=== drawio-gen 검증기 회귀 테스트 ===")
for path in fixtures:
    name = os.path.basename(path)
    if name not in EXPECTED:
        continue
    want_ok, want_text = EXPECTED[name]
    ok, report = validate(path)
    if ok == want_ok and want_text in report:
        print(f"  PASS  {name}")
    else:
        failed.append(name)
        print(f"  FAIL  {name}")
        print(f"        기대: ok={want_ok}, 리포트에 {want_text!r} 포함")
        print(f"        실제: ok={ok}")
        for line in report.splitlines():
            print(f"          {line}")

for name in missing:
    failed.append(name)
    print(f"  FAIL  {name} — 픽스처 파일이 없습니다")
for name in orphan:
    print(f"  WARN  {name} — 기대 결과가 등록되지 않은 픽스처입니다")

total = len(EXPECTED)
print(f"\n{total - len(failed)}/{total} 통과")
sys.exit(1 if failed else 0)
PY
