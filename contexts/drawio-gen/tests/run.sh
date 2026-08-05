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

exit "$FAILED"
