#!/usr/bin/env bash
# drawio-gen 검증기 회귀 테스트
# 각 픽스처는 규칙이 만들어진 실제 실패 사례를 재현한다. layout_toolkit.validate() 를
# 수정할 때 기존 검사가 조용히 죽지 않는지 확인하는 것이 목적이다.
#
# 사용: bash ~/dotfiles/contexts/drawio-gen/tests/run.sh

set -euo pipefail
export QUIET=0

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TESTS_DIR/../scripts" && pwd)"

FAILED=0

python3 - "$TESTS_DIR" "$SCRIPTS_DIR" <<'PY' || FAILED=1
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
    # _abs_geom() 방어 회귀. 둘 다 예전에는 검증기를 크래시시켜(AttributeError /
    # RecursionError) [FAIL] 판정 자체를 삼켰다. 기대는 "특정 위반 검출"이 아니라
    # "죽지 않고 판정에 도달하는 것"이다.
    "ok-missing-geometry.drawio":    (True,  "[OK]"),
    "ok-cyclic-parent.drawio":       (True,  "[OK]"),
    # 090 §1 완료 조건 1번(파싱)의 실패 경로. 예전에는 ParseError 트레이스백으로 빠져나가
    # 나머지 두 조건과 보고 형식이 갈렸다.
    "fail-broken-xml.drawio":        (False, "[FAIL] XML 파싱 실패"),
    # OpenStack 판별(035 §0) 회귀. 이 분기는 픽스처가 하나도 없어, 강조색을 아무 셀에서나
    # 찾는 과잉 매칭이 오래 살아 있었다 — AWS 다이어그램에 빨간 아이콘 하나만 있어도 전체가
    # OpenStack 으로 분류돼 010 §4 가 승인한 AWS 표준 색이 하드 FAIL 났다(실측 재현).
    "ok-aws-emphasis-color-icon.drawio":     (True,  "[OK]"),
    "ok-openstack-native.drawio":            (True,  "[OK]"),
    "fail-openstack-gray-container.drawio":  (False, "[FAIL] OpenStack 컨테이너 색상 위반"),
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

# ---------------------------------------------------------------------------
# CLI 진입점 회귀: 미리보기 실패가 검증 판정을 삼키지 않는지
# ---------------------------------------------------------------------------
# render_preview() 는 matplotlib 을 import 하는데, 이 저장소의 어떤 설치 경로에도 그
# 선언이 없어 신규 환경에는 없다. 그 ImportError 가 SystemExit 앞에서 터지면 검증을
# 통과한 파일과 위반한 파일이 똑같이 exit 1 로 끝나므로, 090 §2~3 이 이 CLI 의
# 종료 코드를 완료 조건의 기계 판정으로 쓰는 만큼 회귀를 고정한다.
echo "--- CLI 종료 코드 (matplotlib 부재 재현) ---"
NOMPL=$(mktemp -d)
trap 'rm -rf "$NOMPL"' EXIT
mkdir -p "$NOMPL/matplotlib"
printf 'raise ImportError("stub: matplotlib not installed")\n' >"$NOMPL/matplotlib/__init__.py"

cli_check() {
  local fixture=$1 want=$2 code=0
  PYTHONPATH="$NOMPL" python3 "$SCRIPTS_DIR/layout_toolkit.py" \
    "$TESTS_DIR/fixtures/$fixture" >"$NOMPL/out" 2>&1 || code=$?
  if [ "$code" -eq "$want" ]; then
    echo "  PASS  CLI $fixture (exit=$code)"
  else
    echo "  FAIL  CLI $fixture — 기대 exit=$want / 실제 exit=$code"
    sed 's/^/          /' "$NOMPL/out" | tail -3
    FAILED=1
  fi
}

cli_check ok-baseline.drawio 0
cli_check fail-duplicate-id.drawio 1
cli_check fail-broken-xml.drawio 1

# 파싱 실패가 트레이스백이 아니라 [FAIL] 로 나오는지. 종료 코드만 보면 예외로 죽은 것과
# 위반을 검출한 것이 구분되지 않으므로 출력 형식까지 고정한다.
PARSE_OUT="$NOMPL/parse-out"
PYTHONPATH="$NOMPL" python3 "$SCRIPTS_DIR/layout_toolkit.py" \
  "$TESTS_DIR/fixtures/fail-broken-xml.drawio" >"$PARSE_OUT" 2>&1 || true
if grep -qF "[FAIL] XML 파싱 실패" "$PARSE_OUT" && ! grep -q "Traceback" "$PARSE_OUT"; then
  echo "  PASS  파싱 실패를 트레이스백 없이 [FAIL] 로 보고"
else
  echo "  FAIL  파싱 실패 보고 형식 — 트레이스백이 남았거나 [FAIL] 이 없습니다"
  sed 's/^/          /' "$PARSE_OUT" | head -4
  FAILED=1
fi

# ---------------------------------------------------------------------------
# check_icon_urls 회귀: 죽은 링크와 네트워크 미지원를 구분하는지
# ---------------------------------------------------------------------------
# urlopen 이 4xx 를 HTTPError 로 올리는데 예전에는 그것을 일반 except 가 삼켜, 죽은
# 링크가 전부 [INFO](확인 미지원)로 강등됐다. 문서(090 §7)가 약속한 [WARN] 이 한 번도
# 나오지 않았다. 네트워크 없이 판정하기 위해 로컬 404 서버를 띄운다.
echo "--- check_icon_urls 죽은 링크 분류 ---"
python3 - "$SCRIPTS_DIR" <<'PY' || FAILED=1
import sys, os, tempfile, threading
from http.server import BaseHTTPRequestHandler, HTTPServer

sys.path.insert(0, sys.argv[1])
from layout_toolkit import check_icon_urls


class Handler(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.send_response(404)
        self.end_headers()

    def log_message(self, *args):
        pass


srv = HTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
url = f"http://127.0.0.1:{srv.server_address[1]}/dead-icon.png"

xml = f'''<mxfile><diagram><mxGraphModel><root>
<mxCell id="0"/><mxCell id="1" parent="0"/>
<mxCell id="icon" vertex="1" parent="1" style="image={url};"><mxGeometry x="0" y="0" width="60" height="60" as="geometry"/></mxCell>
</root></mxGraphModel></diagram></mxfile>'''
path = tempfile.mktemp(suffix=".drawio")
with open(path, "w", encoding="utf-8") as fh:
    fh.write(xml)

report = check_icon_urls(path, timeout=5)
os.unlink(path)
srv.shutdown()

if "[WARN]" in report and "404" in report:
    print("  PASS  404 응답을 [WARN] 으로 분류")
    sys.exit(0)
print("  FAIL  404 응답이 [WARN] 으로 분류되지 않음")
for line in report.splitlines():
    print(f"          {line}")
sys.exit(1)
PY

# 아이콘 URL에 쿼리스트링이 있으면(...?v=2&size=64) style 안의 & 가 날것으로 나가
# .drawio 파일 전체가 XML 파싱 불가가 됐다 — draw.io 가 파일을 아예 열지 못한다.
# 생성물이 항상 유효한 XML인지, 그러면서 URL이 원형 그대로 복원되는지(과잉/이중
# 이스케이프 없음) 양쪽을 함께 고정한다.
echo "--- 생성 XML 이스케이프 (쿼리스트링 URL) ---"
python3 - "$SCRIPTS_DIR" <<'PY' || FAILED=1
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, sys.argv[1])
from layout_toolkit import Diagram

URL_A = "https://cdn.example.com/i.png?v=2&size=64"
URL_B = "https://cdn.example.com/vm.svg?a=1&b=2"

d = Diagram()
d.thirdparty_icon("n1", "1", "Tool", 0, 0, URL_A)
d.azure_icon("n2", "1", "VM", 100, 0, URL_B)
d.edge("e1", "n1", "n2", "링크 & 라벨")

xml = d.to_xml()
try:
    root = ET.fromstring(xml)
except ET.ParseError as e:
    print(f"  FAIL  & 포함 URL로 생성한 XML이 파싱 불가: {e}")
    sys.exit(1)

restored = set()
for c in root.iter("mxCell"):
    for part in (c.get("style") or "").split(";"):
        if part.startswith("image="):
            restored.add(part[len("image="):])

missing = {URL_A, URL_B} - restored
if missing:
    print(f"  FAIL  URL이 원형으로 복원되지 않음(과잉/이중 이스케이프 의심): {sorted(missing)}")
    print(f"          복원된 값: {sorted(restored)}")
    sys.exit(1)

print("  PASS  쿼리스트링 URL 포함 시에도 유효한 XML + URL 원형 보존")
sys.exit(0)
PY

# ---------------------------------------------------------------------------
# 레이아웃 계산 헬퍼 단위 테스트
# ---------------------------------------------------------------------------
# 이 헬퍼들(§10 규칙의 구현체)은 픽스처 기반 validate() 검사와 달리 호출 흔적이 전혀 없어
# 회귀 테스트가 0건이었다. 실제로 grid() 가 아이콘 수와 무관하게 cols 기준으로 폭을 내
# "빈 공간 과다"(§10, 상단 상수 주석) 버그가 그대로 살아 있었다. 계산식을 고정한다.
echo "--- 레이아웃 계산 헬퍼 (grid/hstack/vstack/uniform_row/subnet_box_size) ---"
layout_status=0
python3 - "$SCRIPTS_DIR" <<'PY' || layout_status=$?
import sys
sys.path.insert(0, sys.argv[1])
from layout_toolkit import (grid, hstack, vstack, offset_by_header, row_height,
                            uniform_row, subnet_box_size, IW, IH, GX, GY, PAD, GAP_SIBLING)

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  PASS  {name}")
    else:
        failures.append(name)
        print(f"  FAIL  {name}")
        if detail:
            print(f"        {detail}")


# grid: 폭은 "실제로 채워진 열 수" 기준이어야 한다. cols 를 그대로 쓰면 아이콘 2개짜리
# 서브넷이 4칸 폭으로 그려진다(실측 190px 낭비).
pos, w, h = grid(2, 4)
check("grid(2,4) 폭은 채워진 2열 기준", w == 2 * IW + GX, f"w={w}, 기대={2 * IW + GX}")
pos4, w4, h4 = grid(4, 4)
check("grid(4,4) 폭은 4열 기준(가득 찬 행은 종전과 동일)", w4 == 4 * IW + 3 * GX, f"w={w4}")
# 좌표와 폭의 정합: 마지막 아이콘의 오른쪽 끝이 pad + w 와 정확히 맞아야 한다.
for n, cols in ((1, 3), (2, 4), (3, 3), (4, 4), (5, 4), (7, 3)):
    p, gw, gh = grid(n, cols)
    right = max(x for x, _ in p) + IW - PAD
    bottom = max(y for _, y in p) + IH - PAD
    check(f"grid({n},{cols}) 폭/높이가 실제 아이콘 경계와 일치", gw == right and gh == bottom,
          f"w={gw}(실측 {right}), h={gh}(실측 {bottom})")
check("grid(0,4) 은 빈 결과", grid(0, 4) == ([], 0, 0), f"{grid(0, 4)}")
# 행 수 계산(올림)은 종전 동작 유지.
check("grid(5,4) 은 2행", grid(5, 4)[2] == 2 * IH + GY, f"h={grid(5, 4)[2]}")

xs, tw = hstack([100, 200, 50])
check("hstack 좌표/전체폭", xs == [0, 130, 360] and tw == 410, f"xs={xs}, tw={tw}")
check("hstack 빈 입력", hstack([]) == ([], 0), f"{hstack([])}")
ys, th = vstack([80, 120])
check("vstack 좌표/전체높이", ys == [0, 110] and th == 230, f"ys={ys}, th={th}")
check("vstack 빈 입력", vstack([]) == ([], 0), f"{vstack([])}")
check("offset_by_header", offset_by_header([0, 110], 45) == [45, 155])
check("row_height 최댓값", row_height(100, 250, 180) == 250)
check("row_height 빈 입력", row_height() == 0)
check("uniform_row 높이 통일", uniform_row((100, 80), (200, 150)) == [(100, 150), (200, 150)])
check("uniform_row 빈 입력", uniform_row() == [])
check("subnet_box_size 역산", subnet_box_size(155, 60) == (155 + PAD * 2, 45 + 60 + PAD))
check("GAP_SIBLING 기본값이 hstack/vstack 에 적용", hstack([10, 10])[0][1] == 10 + GAP_SIBLING)

print(f"\n{'실패 없음' if not failures else '실패: ' + ', '.join(failures)}")
sys.exit(1 if failures else 0)
PY
if [ "$layout_status" -ne 0 ]; then FAILED=1; fi

# ---------------------------------------------------------------------------
# 미리보기 보조 함수 + 아이콘 열거값 검증
# ---------------------------------------------------------------------------
# render_preview() 는 matplotlib 을 요구해 이 저장소 어디에도 설치 선언이 없다(위 CLI
# 회귀 참조). 그래서 그 안에 중첩돼 있던 순수 계산 두 개를 모듈 레벨로 올려 여기서 직접
# 고정한다 — 라벨 좌표 선택과 style 값 추출은 matplotlib 없이도 검증 가능한 로직이다.
echo "--- 미리보기 보조 함수 (_edge_label_pos / _style_val) + 아이콘 열거값 ---"
preview_status=0
python3 - "$SCRIPTS_DIR" <<'PY' || preview_status=$?
import sys
sys.path.insert(0, sys.argv[1])
from layout_toolkit import Diagram, _edge_label_pos, _style_val

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  PASS  {name}")
    else:
        failures.append(name)
        print(f"  FAIL  {name}")
        if detail:
            print(f"        {detail}")


# waypoint 없는 엣지(점 2개)가 가장 흔한 경우다. 예전에는 이 인덱스가 도착점이라
# 라벨이 타깃 도형 위에 겹쳐 찍혔고, 한 노드로 여러 엣지가 들어오면 그 자리에 포개졌다.
src, tgt = (100.0, -50.0), (400.0, -50.0)
check("_edge_label_pos: waypoint 없는 엣지는 선분 중점",
      _edge_label_pos([src, tgt]) == (250.0, -50.0), f"{_edge_label_pos([src, tgt])}")
check("_edge_label_pos: 라벨이 도착점에 겹치지 않음",
      _edge_label_pos([src, tgt]) != tgt)
check("_edge_label_pos: waypoint 1개면 그 점",
      _edge_label_pos([src, (250.0, -120.0), tgt]) == (250.0, -120.0))
check("_edge_label_pos: waypoint 2개면 가운데 선분의 중점",
      _edge_label_pos([src, (200.0, -120.0), (300.0, -120.0), tgt]) == (250.0, -120.0))

# strokeColor=none 은 "테두리 없음"이라는 명시적 선언이므로 그대로 전달돼야 한다.
# 기본값으로 치환하면 미리보기에만 검은 테두리가 생겨 실제 렌더링과 달라진다.
check("_style_val: none 을 기본값으로 치환하지 않음",
      _style_val("fillColor=#fff;strokeColor=none;", "strokeColor", "black") == "none")
check("_style_val: 키가 없으면 기본값",
      _style_val("fillColor=#fff;", "strokeColor", "black") == "black")
check("_style_val: 값에 = 가 있어도 통째로 반환",
      _style_val("image=https://x/y?a=1&b=2;html=1;", "image", "") == "https://x/y?a=1&b=2")
check("_style_val: 접두사가 같은 다른 키에 오매치되지 않음",
      _style_val("fontColor=#111;fillColor=#222;", "fillColor", "?") == "#222")

# 열거값 검증: shape/shape_name 과 동일하게 emphasis 오타도 차단해야 한다.
d = Diagram()
try:
    d.openstack_icon("a", "1", "X", 0, 0, emphasis="bule")
    check("openstack_icon: 잘못된 emphasis 차단", False, "ValueError 가 발생하지 않았습니다")
except ValueError:
    check("openstack_icon: 잘못된 emphasis 차단", True)
d2 = Diagram()
d2.openstack_icon("b", "1", "Nova", 0, 0, emphasis="blue")
check("openstack_icon: 유효한 emphasis 는 그대로 적용", "strokeColor=#4A90D9" in d2.cells[0])
d3 = Diagram()
d3.openstack_icon("c", "1", "Keystone", 0, 0)
check("openstack_icon: emphasis=None 은 검정 테두리",
      "strokeColor=#000000" in d3.cells[0] and "strokeWidth=2" in d3.cells[0])

print(f"\n{'실패 없음' if not failures else '실패: ' + ', '.join(failures)}")
sys.exit(1 if failures else 0)
PY
if [ "$preview_status" -ne 0 ]; then FAILED=1; fi

exit "$FAILED"
