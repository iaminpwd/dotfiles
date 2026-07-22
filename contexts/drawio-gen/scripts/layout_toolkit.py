#!/usr/bin/env python3
"""
drawio-gen 스킬 공용 레이아웃 툴킷.

010-drawio-xml-standard.md §10(레이아웃 계산 원칙)을 코드로 강제하기 위한 헬퍼 모음.
다이어그램 생성 스크립트에서 이 모듈을 import해서 쓰고, 좌표를 손으로
하드코딩하지 마십시오. 실제 his-infra 아키텍처 다이어그램 작업(2026-07-21)에서
겪은 버그(빈 공간 과다, 형제 컨테이너 겹침, 헤더-자식 텍스트 겹침, 계단식 정렬)를
재발 방지하기 위해 만들어졌습니다.

사용 예:
    from layout_toolkit import Diagram, grid, hstack, vstack

    d = Diagram()
    d.cloud_shape("internet", "1", "Internet", 620, 20, 140, 70)
    d.container("vpc1", "region", "VPC 1<br>CIDR: 10.0.0.0/16", x, y, w, h, "#147E40", 40)
    pos, w, h = grid(3, 3)  # 아이콘 3개, 3열 격자
    for (iid, label, shape, color), (ix, iy) in zip(items, pos):
        d.aws_icon(iid, "sub_pub_a", label, ix, iy, shape, color)
    d.save("architecture.drawio")
    ok, errors = validate(d.cells)
"""

# ────────────────────────────────────────────────────────────────
# 레이아웃 상수 (010 §2.1, §2.2 표준값)
# ────────────────────────────────────────────────────────────────
IW, IH = 60, 60          # 표준 아이콘 크기
IW_SMALL, IH_SMALL = 40, 40  # ENI 등 소형 커넥터 아이콘 크기
GX, GY = 35, 70          # 아이콘 간 기본 간격 (GY는 2줄 라벨 공간 포함)
# 사용자가 선호 스타일로 지목한 참고 다이어그램(his-infra-architecture선.drawio, 2026-07-22)의
# 실측 간격에 맞춘 값. 과거 "빈 공간 과다" 버그(§10) 재발 방지를 위해 PAD=20/GX=30/GY=55로
# 타이트하게 줄였다가, his-infra 재생성 결과가 "너무 빡빡해 보인다"는 피드백을 받아 중간 수준으로
# 다시 넓혔다. 콘텐츠 기준 역산 원칙(§10 "컨테이너 크기는 콘텐츠로부터 역산")은 그대로 유지하고
# 간격 상수만 조정한 것이므로, 이 값을 더 키우더라도 고정 캔버스 크기를 하드코딩하지는 말 것.
PAD = 25                 # 컨테이너 내부 여백
HEADER_SUBNET = 45       # Subnet 헤더 높이
HEADER_VPC = 40          # VPC/VNet 헤더 높이
HEADER_REGION = 30       # Cloud/Region 헤더 높이


# ────────────────────────────────────────────────────────────────
# 레이아웃 계산 헬퍼 — §10 규칙을 코드로 강제
# ────────────────────────────────────────────────────────────────
def grid(n, cols, iw=IW, ih=IH, gx=GX, gy=GY, pad=PAD):
    """n개 아이콘을 cols열 격자로 배치. PAD 기준 상대좌표 목록과 콘텐츠(w,h) 반환.

    §10 "노드 5개 초과 시 격자/스택 계산 함수 사용" 규칙의 구현체.
    아이콘을 한 줄로만 쭉 늘어놓지 말고 이 함수로 감싸십시오.
    """
    pos = [(pad + (i % cols) * (iw + gx), pad + (i // cols) * (ih + gy)) for i in range(n)]
    rows = -(-n // cols) if n else 0
    w = cols * iw + (cols - 1) * gx if n else 0
    h = rows * ih + (rows - 1) * gy if n else 0
    return pos, w, h


def hstack(sizes, gap=30):
    """가로로 나열할 요소들의 크기(width) 목록 → 각 요소의 x좌표 목록, 전체 너비.

    §10 "형제 간 간격은 고정 gap 상수로 관리" 규칙의 구현체.
    """
    xs, x = [], 0
    for w in sizes:
        xs.append(x)
        x += w + gap
    return xs, (x - gap if sizes else 0)


def vstack(sizes, gap=30):
    """세로로 나열할 요소들의 크기(height) 목록 → 각 요소의 y좌표 목록, 전체 높이."""
    ys, y = [], 0
    for h in sizes:
        ys.append(y)
        y += h + gap
    return ys, (y - gap if sizes else 0)


def offset_by_header(ys, header_height):
    """§10 "헤더 높이만큼 자식 y 오프셋 필수" 규칙 — vstack 결과에 부모 헤더 높이를 더함.

    이걸 빼먹으면 부모 컨테이너 제목과 첫 번째 자식의 헤더 텍스트가 겹칩니다.
    (his-infra 작업에서 실제로 이 버그가 2번 발생했습니다.)
    """
    return [y + header_height for y in ys]


def row_height(*heights):
    """같은 행에 놓일 형제 컨테이너들의 자연 높이 목록 → 통일할 행 높이(최댓값).

    §10 "같은 시각적 행의 형제 컨테이너는 높이를 통일" 규칙의 구현체.
    반환값을 그 행의 모든 컨테이너 height 인자로 동일하게 사용하십시오.
    """
    return max(heights) if heights else 0


def uniform_row(*wh_pairs):
    """행에 나란히 배치할 (width, height) 목록 → 높이를 행 최댓값으로 통일한 (width, height) 목록.

    row_height()는 "통일할 값"만 계산해줄 뿐 실제로 각 컨테이너에 되돌려 적용하는 것은
    호출자 책임이었다. 실제 his-infra 재생성 작업(2026-07-22)에서 row_height()로 값만
    구하고 정작 각 subnet의 height 인자에는 반영하지 않아 형제 박스 바닥선이 어긋나는
    회귀가 발생했다 — "계산은 했지만 적용을 잊는" 실수를 원천 차단하기 위해, 각 컨테이너를
    만들 때 이 함수가 반환한 (w, h)를 그대로 height 인자로 쓰도록 강제한다.
    사용 예: (pe_w, pe_h), (pk_w, pk_h), (pm_w, pm_h) = uniform_row((pe_w, pe_h0), (pk_w, pk_h0), (pm_w, pm_h0))
    """
    h = max((hh for _, hh in wh_pairs), default=0)
    return [(w, h) for w, _ in wh_pairs]


def subnet_box_size(content_w, content_h, header=HEADER_SUBNET, extra_below=0, pad=PAD):
    """아이콘 격자 콘텐츠 크기 → 서브넷 컨테이너 전체 (width, height).

    §10 "컨테이너 크기는 콘텐츠로부터 역산" 규칙의 구현체.
    """
    return content_w + pad * 2, header + content_h + extra_below + pad


# ────────────────────────────────────────────────────────────────
# XML 셀 빌더
# ────────────────────────────────────────────────────────────────
def esc(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;")
             .replace(">", "&gt;").replace('"', "&quot;"))


class Diagram:
    def __init__(self):
        self.cells = []

    def add(self, id_, parent, value, style, x, y, w, h):
        self.cells.append(
            f'<mxCell id="{id_}" value="{esc(value)}" style="{style}" vertex="1" parent="{parent}">'
            f'<mxGeometry x="{x:.0f}" y="{y:.0f}" width="{w:.0f}" height="{h:.0f}" as="geometry"/></mxCell>'
        )

    def edge(self, id_, source, target, value="", dashed=False, bidir=False, parent="1", points=None):
        """points: [(x, y), ...] 중간 경유점 목록(부모 컨테이너 좌표계 기준).
        2단계 이상 컨테이너를 가로지르는 장거리 엣지의 자동 라우팅이 지저분해 보이는 문제(010 §10)를
        방지하기 위한 명시적 waypoint 지정용."""
        style = "edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;strokeWidth=2;strokeColor=#555555;"
        if dashed:
            style += "dashed=1;"
        style += ("startArrow=classic;" if bidir else "") + "endArrow=classic;"
        if value:
            style += "labelBackgroundColor=#ffffff;"
        pts_xml = ""
        if points:
            pts = "".join(f'<mxPoint x="{px:.0f}" y="{py:.0f}"/>' for px, py in points)
            pts_xml = f'<Array as="points">{pts}</Array>'
        self.cells.append(
            f'<mxCell id="{id_}" value="{esc(value)}" style="{style}" edge="1" parent="{parent}" '
            f'source="{source}" target="{target}"><mxGeometry relative="1" as="geometry">{pts_xml}</mxGeometry></mxCell>'
        )

    def container(self, id_, parent, value, x, y, w, h, stroke, header, dashed=False, fill="none", font_color=None):
        fc = font_color or stroke
        style = (f"swimlane;whiteSpace=wrap;html=1;fillColor={fill};strokeColor={stroke};"
                 f"startSize={header};fontStyle=1;fontColor={fc};swimlaneLine=0;")
        if dashed:
            style += "dashed=1;"
        self.add(id_, parent, value, style, x, y, w, h)

    def aws_icon(self, id_, parent, value, x, y, shape, color, w=IW, h=IH):
        style = (f"outlineConnect=0;fontColor=#232F3E;gradientColor=none;fillColor={color};strokeColor=none;"
                 f"dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;"
                 f"aspect=fixed;shape=mxgraph.aws4.{shape};")
        self.add(id_, parent, value, style, x, y, w, h)

    def azure_icon(self, id_, parent, value, x, y, image_path, w=IW, h=IH):
        style = (f"image;aspect=fixed;html=1;points=[];align=center;fontSize=10;"
                 f"image={image_path};verticalLabelPosition=bottom;verticalAlign=top;")
        self.add(id_, parent, value, style, x, y, w, h)

    def thirdparty_icon(self, id_, parent, value, x, y, url, w=IW, h=IH):
        style = (f"shape=image;html=1;verticalAlign=top;verticalLabelPosition=bottom;"
                 f"labelBackgroundColor=#ffffff;imageAspect=0;aspect=fixed;image={url};")
        self.add(id_, parent, value, style, x, y, w, h)

    def gitlab_icon(self, id_, parent, value, x, y, w=IW, h=IH):
        style = ("shape=mxgraph.ibm_cloud.logo--gitlab;fillColor=#E24329;strokeColor=none;html=1;"
                 "verticalLabelPosition=bottom;verticalAlign=top;labelBackgroundColor=#ffffff;")
        self.add(id_, parent, value, style, x, y, w, h)

    def note(self, id_, parent, value, x, y, w, h, font_size=10, color="#555555", align="left"):
        style = f"text;html=1;align={align};verticalAlign=top;fontSize={font_size};fontColor={color};whiteSpace=wrap;"
        self.add(id_, parent, value, style, x, y, w, h)

    def cloud_shape(self, id_, parent, value, x, y, w, h):
        self.add(id_, parent, value, "ellipse;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;", x, y, w, h)

    def to_xml(self, diagram_name="Architecture"):
        return f'''<mxfile host="app.diagrams.net" agent="Mozilla/5.0">
  <diagram id="arch" name="{diagram_name}">
    <mxGraphModel dx="1800" dy="1600" grid="0" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="2000" pageHeight="1400" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        {''.join(self.cells)}
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
'''

    def save(self, path, diagram_name="Architecture"):
        with open(path, "w", encoding="utf-8") as f:
            f.write(self.to_xml(diagram_name))


# ────────────────────────────────────────────────────────────────
# 절대 좌표 변환 (validate/render_preview 공용)
# ────────────────────────────────────────────────────────────────
def _abs_geom(cells, cid):
    """cid의 부모 체인을 따라가며 절대 좌표 (x, y, w, h)를 계산한다."""
    if cid in ("0", "1", None) or cid not in cells:
        return 0.0, 0.0, 0.0, 0.0
    c = cells[cid]
    g = c.find("mxGeometry")
    x, y = float(g.get("x", 0)), float(g.get("y", 0))
    w, h = float(g.get("width", 0)), float(g.get("height", 0))
    px, py, _, _ = _abs_geom(cells, c.get("parent"))
    return x + px, y + py, w, h


# ────────────────────────────────────────────────────────────────
# 090 검증 + 겹침 검사 (090-validation-standard.md §1의 실제 구현)
# ────────────────────────────────────────────────────────────────
def validate(path):
    """090 문서 §1의 3가지 완료 조건(파싱/ID 중복/끊어진 참조) + 형제 노드 겹침 검사.

    반환: (ok: bool, report: str)
    """
    import re
    import html as _html
    import xml.etree.ElementTree as ET
    from collections import defaultdict

    root = ET.parse(path).getroot()
    cells = {c.get("id"): c for c in root.findall(".//mxCell") if c.get("id")}
    lines = []

    ids = list(cells.keys())
    dup = [i for i in ids if ids.count(i) > 1]
    if dup:
        lines.append(f"[FAIL] 중복 ID: {sorted(set(dup))}")
    idset = set(ids)
    missing = [(c.get("id"), a, c.get(a)) for c in cells.values()
               for a in ("source", "target") if c.get(a) and c.get(a) not in idset]
    if missing:
        lines.append(f"[FAIL] 끊어진 참조: {missing}")
    color_violations = []

    # 형제 노드 간 사각형 겹침 검사 (§10 신규 규칙)
    def abs_pos(cid):
        return _abs_geom(cells, cid)

    siblings = defaultdict(list)
    for cid, c in cells.items():
        if cid in ("0", "1") or c.get("vertex") != "1":
            continue
        siblings[c.get("parent")].append(cid)

    def overlaps(a, b):
        ax, ay, aw, ah = abs_pos(a)
        bx, by, bw, bh = abs_pos(b)
        return not (ax + aw <= bx or bx + bw <= ax or ay + ah <= by or by + bh <= ay)

    for parent, kids in siblings.items():
        for i in range(len(kids)):
            for j in range(i + 1, len(kids)):
                if overlaps(kids[i], kids[j]):
                    lines.append(f"[WARN] 형제 노드 겹침 (parent={parent}): {kids[i]} vs {kids[j]}")

    # 같은 행(row) 형제 컨테이너 높이 통일 검사 (§10 "형제 컨테이너는 높이를 통일")
    # his-infra 재생성 작업(2026-07-22)에서 row_height()/uniform_row()로 통일 높이를
    # 계산해놓고 실제 컨테이너 height 인자에는 반영하지 않아 바닥선이 어긋나는 회귀가
    # 발생했다. 같은 parent 밑에서 y좌표(행 시작선)가 사실상 같은데 height가 다른
    # swimlane 형제가 있으면, uniform_row() 적용을 빠뜨린 것으로 보고 경고한다.
    EPS = 2.0
    for parent, kids in siblings.items():
        containers = [k for k in kids if "swimlane" in cells[k].get("style", "")]
        rows = defaultdict(list)
        for k in containers:
            _, y, _, h = abs_pos(k)
            rows[round(y / EPS) * EPS].append((k, h))
        for y, items in rows.items():
            if len(items) < 2:
                continue
            heights = [h for _, h in items]
            if max(heights) - min(heights) > EPS:
                ids_h = ", ".join(f"{k}(h={h:.0f})" for k, h in items)
                lines.append(f"[WARN] 행 높이 불일치 (parent={parent}, y≈{y:.0f}): {ids_h} — uniform_row() 적용 누락 의심")

    # 아이콘 라벨 텍스트 폭 초과 검사 (010 §2.2/§8)
    # verticalLabelPosition=bottom 아이콘 스타일에는 whiteSpace=wrap이 없어서 실제 drawio
    # 렌더링에서 라벨이 자동 줄바꿈되지 않는다. 서브라벨 문장이 길면(예: Lambda(x4) 함수명
    # 나열) 아이콘 폭(60px)을 크게 넘어 옆 아이콘과 겹쳐 보인다 — 글자수×폰트크기 근사식으로
    # 위험을 사전 경고한다. 실제 텍스트 렌더링 폭과 정확히 일치하지 않는 휴리스틱이므로 [WARN]만.
    def plain_lines(value):
        raw_lines = re.split(r"<br\s*/?>", value or "")
        out = []
        for ln in raw_lines:
            m = re.search(r"font-size:\s*(\d+)px", ln)
            size = int(m.group(1)) if m else 12
            text = _html.unescape(re.sub(r"<[^>]+>", "", ln)).strip()
            if text:
                out.append((text, size))
        return out

    # 예산(budget)은 넉넉하게 잡는다 — "Internet Gateway"/"Customer Gateway"처럼 020 문서
    # 예시에 그대로 나오는 표준 라벨까지 매번 걸리면 경고가 무의미해진다(실측 보정, 2026-07-22).
    # 진짜 겹침 위험이 있는 문장형 서브라벨(함수명 나열 등)만 잡히도록 여유를 크게 둔다.
    for cid, c in cells.items():
        style = c.get("style", "")
        if "swimlane" in style or "whiteSpace=wrap" in style or "verticalLabelPosition=bottom" not in style:
            continue
        _, _, w, _ = _abs_geom(cells, cid)
        budget = (w or IW) + GX * 3
        for text, size in plain_lines(c.get("value", "")):
            est = len(text) * size * 0.48
            if est > budget:
                lines.append(f"[WARN] 라벨 폭 초과 의심 (id={cid}): \"{text}\" 추정폭 {est:.0f}px > 여유폭 {budget:.0f}px "
                              f"— whiteSpace=wrap 없는 아이콘 라벨은 자동 줄바꿈 안 됨, 문장을 줄이거나 <br>로 나누십시오")

    # 컨테이너(swimlane) 색상 팔레트 준수 검사 (010 §4 표 기준)
    # his-infra 작업에서 priv_main/priv_monitor/vpc2 컨테이너가 팔레트에 없는 색(#8C4FFF)을
    # 임의로 쓴 채 통과된 적이 있어, 사람이 매번 표와 대조하지 않아도 되도록 기계적으로 강제한다.
    APPROVED_CONTAINER_COLORS = {
        "#147E40",  # VPC/VNet 테두리
        "#007CBC",  # Subnet 테두리(AWS) / Region(AWS)
        "#0072C6",  # Subnet 테두리(Azure) / Region(Azure) / ACA Environment
        "#555555",  # 온프레미스 테두리
        "#232F3E",  # AWS/Azure Cloud 테두리
        "#D15100",  # Auto Scaling Group
        "#888888",  # 참고용 회색 그룹핑(예: 비활성/수동관리 표시) — 팀 컨벤션 예외 허용
    }
    for cid, c in cells.items():
        style = c.get("style", "")
        if "swimlane" not in style:
            continue
        m = re.search(r"strokeColor=(#[0-9A-Fa-f]{6})", style)
        if m and m.group(1).upper() not in APPROVED_CONTAINER_COLORS:
            color_violations.append((cid, m.group(1)))
            lines.append(f"[FAIL] 컨테이너 팔레트 위반 (010 §4): id={cid} strokeColor={m.group(1)} "
                         f"(허용값: {sorted(APPROVED_CONTAINER_COLORS)})")

    ok = not dup and not missing and not color_violations
    if ok and not lines:
        lines.append(f"[OK] {len(ids)}개 mxCell, 중복/끊어진 참조/형제 겹침/라벨폭/팔레트 위반 없음")
    return ok, "\n".join(lines)


# ────────────────────────────────────────────────────────────────
# 엣지 포함 간이 렌더링 (010 §10 "생성 직후 렌더링 검증"의 실제 구현체)
# ────────────────────────────────────────────────────────────────
def render_preview(path, out_png):
    """컨테이너/아이콘 사각형 + 엣지(연결선, waypoint 포함)까지 그린 PNG를 저장한다.

    과거에는 다이어그램 생성 스크립트마다 박스만 그리는 임시 렌더러를 매번 새로 짜서,
    엣지 라우팅이 다른 컨테이너를 뚫고 지나가는지 등을 한 번도 육안 검증하지 못하는
    구멍이 있었다(2026-07-22 발견). Read 도구로 이 PNG를 열어 박스 정렬뿐 아니라
    연결선 경로까지 확인한 뒤에만 완료를 선언하십시오.
    """
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import matplotlib.patches as patches
    import xml.etree.ElementTree as ET

    root = ET.parse(path).getroot()
    cells = {c.get("id"): c for c in root.findall(".//mxCell") if c.get("id")}

    fig, ax = plt.subplots(figsize=(24, 14))
    maxx = maxy = 0.0

    def style_val(style, key, default):
        for part in style.split(";"):
            if part.startswith(key + "="):
                v = part.split("=", 1)[1]
                return v if v != "none" else default
        return default

    for cid, c in cells.items():
        if cid in ("0", "1") or c.get("vertex") != "1":
            continue
        x, y, w, h = _abs_geom(cells, cid)
        style = c.get("style", "")
        is_container = "swimlane" in style
        fill = style_val(style, "fillColor", "none")
        stroke = style_val(style, "strokeColor", "black")
        rect = patches.Rectangle((x, -y - h), w, h,
                                  linewidth=1.8 if is_container else 0.8, edgecolor=stroke,
                                  facecolor=fill, alpha=0.5 if is_container else 0.85)
        ax.add_patch(rect)
        label = (c.get("value") or "").split("<br>")[0].replace("&amp;", "&")
        ax.text(x + 3, -y - 10, label[:34], fontsize=7.5 if is_container else 6, va="top")
        maxx, maxy = max(maxx, x + w), max(maxy, y + h)

    for cid, c in cells.items():
        if c.get("edge") != "1":
            continue
        src, tgt = c.get("source"), c.get("target")
        if not src or not tgt or src not in cells or tgt not in cells:
            continue
        sx, sy, sw, sh = _abs_geom(cells, src)
        tx, ty, tw, th = _abs_geom(cells, tgt)
        parent = c.get("parent")
        pgx, pgy, _, _ = _abs_geom(cells, parent)
        pts = [(sx + sw / 2, -(sy + sh / 2))]
        geom = c.find("mxGeometry")
        arr = geom.find("Array") if geom is not None else None
        if arr is not None:
            for mp in arr.findall("mxPoint"):
                px, py = float(mp.get("x", 0)), float(mp.get("y", 0))
                pts.append((px + pgx, -(py + pgy)))
        pts.append((tx + tw / 2, -(ty + th / 2)))
        dashed = "dashed=1" in c.get("style", "")
        xs, ys = zip(*pts)
        ax.plot(xs, ys, color="#555555", linewidth=1.2, linestyle="--" if dashed else "-", zorder=5)
        val = (c.get("value") or "").strip()
        if val:
            mx, my = pts[len(pts) // 2]
            ax.text(mx, my, val, fontsize=6.5, color="#333333",
                    bbox=dict(facecolor="white", edgecolor="none", pad=0.5), zorder=6)

    ax.set_xlim(-20, maxx + 20)
    ax.set_ylim(-maxy - 20, 20)
    ax.set_aspect("equal")
    ax.axis("off")
    plt.tight_layout()
    plt.savefig(out_png, dpi=130)
    plt.close(fig)
    return out_png


# ────────────────────────────────────────────────────────────────
# 서드파티 아이콘 URL 생존 확인 (040 문서, 네트워크 필요 — PREFER, 완료 조건 아님)
# ────────────────────────────────────────────────────────────────
def check_icon_urls(path, timeout=3):
    """thirdparty_icon()이 참조하는 image= URL이 실제로 응답하는지 HEAD 요청으로 확인한다.

    네트워크가 없거나 타임아웃이면 [FAIL]이 아니라 [INFO](확인 불가)로만 표시한다 —
    오프라인 환경에서 이 검사 자체가 전체 완료 조건을 막아서는 안 되기 때문이다.
    """
    import re
    import xml.etree.ElementTree as ET
    import urllib.request

    root = ET.parse(path).getroot()
    urls = set()
    for c in root.findall(".//mxCell"):
        m = re.search(r"image=(https?://[^;\"]+)", c.get("style", ""))
        if m:
            urls.add(m.group(1))

    if not urls:
        return "[OK] 서드파티 이미지 URL 없음"

    lines = []
    for url in sorted(urls):
        try:
            req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                if resp.status >= 400:
                    lines.append(f"[WARN] 아이콘 URL 응답 이상 (status={resp.status}): {url}")
        except Exception as e:
            lines.append(f"[INFO] 아이콘 URL 확인 불가(네트워크/타임아웃, FAIL 아님): {url} ({e.__class__.__name__})")
    if not lines:
        lines.append(f"[OK] 서드파티 아이콘 URL {len(urls)}개 모두 응답 정상")
    return "\n".join(lines)


if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print("usage: python3 layout_toolkit.py <path-to.drawio>")
        raise SystemExit(1)
    ok, report = validate(sys.argv[1])
    print(report)
    preview_path = sys.argv[1].rsplit(".", 1)[0] + "-preview.png"
    render_preview(sys.argv[1], preview_path)
    print(f"[INFO] 엣지 포함 렌더링 미리보기 저장: {preview_path}")
    raise SystemExit(0 if ok else 1)
