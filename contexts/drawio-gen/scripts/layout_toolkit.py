#!/usr/bin/env python3
"""
drawio-gen 스킬 공용 레이아웃 툴킷.

010-drawio-xml-standard.md §10(레이아웃 계산 원칙)을 코드로 강제하기 위한 헬퍼 모음.
다이어그램 생성 스크립트에서 이 모듈을 import해서 쓰고, 좌표를 손으로
하드코딩하지 마십시오. 실제 아키텍처 다이어그램 작업에서 겪은 버그(빈 공간 과다,
형제 컨테이너 겹침, 헤더-자식 텍스트 겹침, 계단식 정렬)를 재발 방지하기 위해
만들어졌습니다.

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
# 사용자가 선호 스타일로 지목한 참고 다이어그램의 실측 간격에 맞춘 값. 과거 "빈 공간
# 과다" 버그(§10) 재발 방지를 위해 PAD=20/GX=30/GY=55로 타이트하게 줄였다가, "너무
# 빡빡해 보인다"는 피드백을 받아 중간 수준으로 다시 넓혔다. 콘텐츠 기준 역산 원칙
# (§10 "컨테이너 크기는 콘텐츠로부터 역산")은 그대로 유지하고 간격 상수만 조정한
# 것이므로, 이 값을 더 키우더라도 고정 캔버스 크기를 하드코딩하지는 말 것.
PAD = 25                 # 컨테이너 내부 여백
# 형제 컨테이너(서브넷/VPC 등) 사이 간격. hstack()/vstack() 이 기본값으로 쓴다.
# 두 함수가 이 상수 대신 30 을 하드코딩하면, 015 §3 "형제 간 간격은 고정 gap 상수로
# 관리" 규칙을 정작 구현체가 지키지 않는 셈이 된다.
# GX/GY 를 여기에 재사용하지 않는 이유: 그 둘은 아이콘 전용 상수이고, 특히 GY(70)는
# 아이콘 아래 2줄 라벨 공간을 포함한 값이라 컨테이너 행 간격으로 쓰면 015 §3 이 예시로
# 드는 수준("서브넷 간 30px, 행 간 25px")의 2배 이상으로 벌어진다.
GAP_SIBLING = 30
HEADER_SUBNET = 45       # Subnet 헤더 높이
HEADER_VPC = 40          # VPC/VNet 헤더 높이
HEADER_REGION = 30       # Cloud/Region 헤더 높이

# 타이포그래피 위계 (050-readability-standard.md) — 글자 크기 들쭉날쭉 방지용 고정값.
# drawio 기본 폰트는 12px라 컨테이너 헤더/아이콘 라벨/서브라벨이 다 같은 크기로 뭉개진다.
FONT_TITLE = 20          # 다이어그램 제목 블록
FONT_HEADER = 13         # 컨테이너(swimlane) 헤더
FONT_LABEL = 12          # 아이콘 메인 라벨
FONT_SUBLABEL = 10       # 아이콘 서브라벨([AZ-A, C] 등)


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
    # 폭은 실제로 채워진 열 수로 낸다. cols 를 그대로 쓰면 아이콘이 열 수보다 적을 때
    # 빈 칸까지 폭에 포함되어(예: grid(2, 4) -> 345px, 실제 콘텐츠 155px) 그 차이가
    # subnet_box_size() 를 타고 컨테이너 폭이 된다 — §10 "컨테이너 크기는 콘텐츠로부터
    # 역산" 위반이자 이 파일 상단 주석이 재발 방지를 명시한 "빈 공간 과다" 그 버그다.
    eff_cols = min(n, cols)
    w = eff_cols * iw + (eff_cols - 1) * gx if n else 0
    h = rows * ih + (rows - 1) * gy if n else 0
    return pos, w, h


def hstack(sizes, gap=GAP_SIBLING):
    """가로로 나열할 요소들의 크기(width) 목록 → 각 요소의 x좌표 목록, 전체 너비.

    §10 "형제 간 간격은 고정 gap 상수로 관리" 규칙의 구현체.
    서브넷/컨테이너 배치용이므로 아이콘 간격(GX)이 아니라 GAP_SIBLING 을 기본으로 쓴다.
    """
    xs, x = [], 0
    for w in sizes:
        xs.append(x)
        x += w + gap
    return xs, (x - gap if sizes else 0)


def vstack(sizes, gap=GAP_SIBLING):
    """세로로 나열할 요소들의 크기(height) 목록 → 각 요소의 y좌표 목록, 전체 높이.

    hstack() 과 같은 이유로 아이콘 간격(GY)이 아니라 GAP_SIBLING 을 기본으로 쓴다.
    """
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
    호출자 책임이었다. row_height()로 값만 구하고 정작 각 subnet의 height 인자에는
    반영하지 않으면 형제 박스 바닥선이 어긋나는 회귀가 생긴다 — "계산은 했지만 적용을
    잊는" 실수를 원천 차단하기 위해, 각 컨테이너를 만들 때 이 함수가 반환한 (w, h)를
    그대로 height 인자로 쓰도록 강제한다.
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
        # style 도 반드시 esc 를 거쳐야 한다. thirdparty_icon()/azure_icon() 이 style 안에
        # image=<URL> 을 그대로 끼워 넣는데, 쿼리스트링이 있는 URL(...?v=2&size=64)의 & 가
        # 날것으로 나가면 .drawio 파일 전체가 XML 파싱 불가가 되어 draw.io 가 열지 못한다
        # (실측 재현). id/parent 도 같은 속성 자리라 동일하게 처리한다.
        self.cells.append(
            f'<mxCell id="{esc(id_)}" value="{esc(value)}" style="{esc(style)}" vertex="1" parent="{esc(parent)}">'
            f'<mxGeometry x="{x:.0f}" y="{y:.0f}" width="{w:.0f}" height="{h:.0f}" as="geometry"/></mxCell>'
        )

    def edge(self, id_, source, target, value="", dashed=False, dotted=False, bidir=False, parent="1", points=None):
        """points: [(x, y), ...] 중간 경유점 목록(부모 컨테이너 좌표계 기준).
        2단계 이상 컨테이너를 가로지르는 장거리 엣지의 자동 라우팅이 지저분해 보이는 문제(015 §4)를
        방지하기 위한 명시적 waypoint 지정용.

        dashed/dotted 구분은 OpenStack 공식 다이어그램 표준(035 §0, docs.openstack.org/
        doc-contrib-guide/diagram-guidelines/general-guidelines.html)의 3종 선 의미를 따른다:
        실선=직접적 관계, dashed=온라인 네트워크로 연결된 객체 그룹, dotted=사람이 입력한
        데이터의 이동 경로(예: 사용자 로그인 폼 제출, 최초 API 요청). 동시에 켜지 않는다."""
        style = "edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;strokeWidth=2;strokeColor=#555555;"
        if dotted:
            style += "dashed=1;dashPattern=1 2;"
        elif dashed:
            style += "dashed=1;"
        style += ("startArrow=classic;" if bidir else "") + "endArrow=classic;"
        if value:
            style += "labelBackgroundColor=#ffffff;"
        pts_xml = ""
        if points:
            pts = "".join(f'<mxPoint x="{px:.0f}" y="{py:.0f}"/>' for px, py in points)
            pts_xml = f'<Array as="points">{pts}</Array>'
        self.cells.append(
            # add() 와 동일하게 모든 속성값을 esc 로 통과시킨다(사유는 add() 주석 참조).
            f'<mxCell id="{esc(id_)}" value="{esc(value)}" style="{esc(style)}" edge="1" parent="{esc(parent)}" '
            f'source="{esc(source)}" target="{esc(target)}"><mxGeometry relative="1" as="geometry">{pts_xml}</mxGeometry></mxCell>'
        )

    def container(self, id_, parent, value, x, y, w, h, stroke, header, dashed=False, fill="none", font_color=None):
        fc = font_color or stroke
        style = (f"swimlane;whiteSpace=wrap;html=1;fillColor={fill};strokeColor={stroke};"
                 f"startSize={header};fontStyle=1;fontSize={FONT_HEADER};fontColor={fc};swimlaneLine=0;")
        if dashed:
            style += "dashed=1;"
        self.add(id_, parent, value, style, x, y, w, h)

    def aws_icon(self, id_, parent, value, x, y, shape, color, w=IW, h=IH):
        # whiteSpace=wrap: 긴 라벨이 옆 아이콘을 침범하지 않고 아이콘 폭(60px) 안에서
        # 자동 줄바꿈되도록 강제 (050-readability-standard.md). 서브라벨은 여전히 <br>로 짧게.
        style = (f"outlineConnect=0;fontColor=#232F3E;gradientColor=none;fillColor={color};strokeColor=none;"
                 f"dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;whiteSpace=wrap;"
                 f"fontSize={FONT_LABEL};aspect=fixed;shape=mxgraph.aws4.{shape};")
        self.add(id_, parent, value, style, x, y, w, h)

    def azure_icon(self, id_, parent, value, x, y, image_path, w=IW, h=IH):
        style = (f"image;aspect=fixed;html=1;points=[];align=center;whiteSpace=wrap;fontSize={FONT_LABEL};"
                 f"image={image_path};verticalLabelPosition=bottom;verticalAlign=top;")
        self.add(id_, parent, value, style, x, y, w, h)

    OPENSTACK_ACCENT = {"blue": "#4A90D9", "red": "#DA1A32", "green": "#2E7D32"}

    def openstack_icon(self, id_, parent, value, x, y, shape="rounded", emphasis=None, w=90, h=70):
        # Keystone/Glance/Horizon 등 컨트롤 플레인 서비스는 draw.io에도 OpenStack
        # 공식 자료에도 아이콘이 없으므로(035-openstack-icon-style-library.md §1-2),
        # 기본 도형(rounded/cylinder/hexagon)으로 표현한다.
        #
        # 색상은 OpenStack 공식 다이어그램 표준(035 §0, docs.openstack.org/doc-contrib-guide/
        # diagram-guidelines/general-guidelines.html, 조회 2026-07-23)을 그대로 따른다:
        # "객체는 기본적으로 검정이어야 하며, 강조가 꼭 필요할 때만 밝은 원색(하늘색/빨강/초록)
        # 중 하나를 쓰고 같은 기능의 객체는 같은 색을 재사용한다." emphasis=None(기본)이면
        # 검정 테두리+흰 배경. emphasis="blue"|"red"|"green"이면 그 원색을 테두리에만 적용해
        # 배경은 흰색으로 유지, 텍스트 라벨 가독성을 지킨다(색을 배경까지 채우면 표준의
        # "hollow middle" 요건과 라벨 대비가 깨진다).
        #
        # [라벨 위치] aws_icon/azure_icon/openstack_native_icon 과 동일하게
        # verticalLabelPosition=bottom(라벨을 도형 "아래"에 배치)을 쓴다 — 사용자가
        # 이 관례(아이콘 계열 공통 스타일)를 선호한다. 대신 기본
        # 크기를 60x60 → 90x70으로 키워, 도형 없는 빈 사각형 아래 여러 줄 라벨이
        # 옆/아래 요소와 겹치지 않을 여유를 확보한다. 이 크기를 쓰는 grid()/hstack()/
        # vstack() 호출의 gy(행 간격)도 라벨 줄 수에 맞게 함께 넉넉히 늘릴 것 —
        # 크기만 키우고 간격을 그대로 두면 다음 행과 다시 겹친다.
        # 도형은 rounded(기본형) / cylinder(데이터 저장소) 2종만 쓴다(035 §2).
        # hexagon 은 폐기됐다 — 공식 표준은 도형에 의미를 부여하지 않고 라벨에
        # 맡기며, 육각형=큐는 보편 관례가 아니라 범례 없이는 오독을 만든다.
        if shape == "hexagon":
            raise ValueError("hexagon 은 035 §2 에서 폐기되었습니다. "
                             "브로커·큐도 rounded 를 쓰고 구분은 라벨로 하십시오.")
        base_map = {
            "rounded": "rounded=1;",
            "cylinder": "shape=cylinder3;",
        }
        if shape not in base_map:
            raise ValueError(f"'{shape}' 은 035 §2 가 허용하는 shape(rounded/cylinder) 중 하나가 아닙니다.")
        base = base_map[shape]
        # emphasis 도 shape/shape_name 과 동일하게 열거값을 강제한다. 예전에는 .get() 폴백이라
        # 오타("bule" 등)가 조용히 검정으로 떨어졌는데, strokeWidth 는 3 그대로여서 "굵기만
        # 강조되고 색은 없는" 아이콘이 나오고 호출자는 오타를 알 방법이 없었다. 035 §0의
        # "같은 기능의 객체는 같은 색을 재사용" 규칙이 그 경로로 조용히 깨진다.
        if emphasis is not None and emphasis not in self.OPENSTACK_ACCENT:
            raise ValueError(f"'{emphasis}' 은 035 §0 이 허용하는 강조색"
                             f"({sorted(self.OPENSTACK_ACCENT)}) 중 하나가 아닙니다. "
                             f"강조가 필요 없으면 emphasis=None 을 쓰십시오.")
        stroke = self.OPENSTACK_ACCENT.get(emphasis, "#000000")
        sw = 3 if emphasis else 2
        style = (f"{base}whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor={stroke};strokeWidth={sw};"
                 f"fontColor=#000000;verticalLabelPosition=bottom;verticalAlign=top;align=center;"
                 f"fontSize={FONT_LABEL};aspect=fixed;")
        self.add(id_, parent, value, style, x, y, w, h)

    def openstack_native_icon(self, id_, parent, value, x, y, shape_name, color="3F51B5", w=IW, h=IH):
        # draw.io 내장 mxgraph.openstack.* 스텐실(035 §1). 18종 테넌트 리소스에
        # 한해서만 유효 — 존재하지 않는 shape_name을 창작하지 말 것.
        # 출처: jgraph/drawio Sidebar-OpenStack.js (조회 2026-07-23).
        valid = {"cinder_volume", "cinder_volumeattachment", "designate_recordset", "designate_zone",
                 "heat_autoscalinggroup", "heat_resourcegroup", "heat_scalingpolicy",
                 "neutron_floatingip", "neutron_floatingipassociation", "neutron_net", "neutron_port",
                 "neutron_router", "neutron_routerinterface", "neutron_securitygroup", "neutron_subnet",
                 "nova_keypair", "nova_server", "swift_container"}
        if shape_name not in valid:
            raise ValueError(f"'{shape_name}' 은 mxgraph.openstack.* 의 18종 스텐실에 없습니다: {sorted(valid)}")
        style = (f"aspect=fixed;sketch=0;pointerEvents=1;shadow=0;dashed=0;html=1;strokeColor=none;"
                 f"labelPosition=center;verticalLabelPosition=bottom;outlineConnect=0;verticalAlign=top;"
                 f"align=center;shape=mxgraph.openstack.{shape_name};fillColor=#{color};"
                 f"whiteSpace=wrap;fontSize={FONT_LABEL};fontColor=#232F3E;")
        self.add(id_, parent, value, style, x, y, w, h)

    def thirdparty_icon(self, id_, parent, value, x, y, url, w=IW, h=IH):
        style = (f"shape=image;html=1;verticalAlign=top;verticalLabelPosition=bottom;whiteSpace=wrap;fontSize={FONT_LABEL};"
                 f"labelBackgroundColor=#ffffff;imageAspect=0;aspect=fixed;image={url};")
        self.add(id_, parent, value, style, x, y, w, h)

    def gitlab_icon(self, id_, parent, value, x, y, w=IW, h=IH):
        style = (f"shape=mxgraph.ibm_cloud.logo--gitlab;fillColor=#E24329;strokeColor=none;html=1;whiteSpace=wrap;"
                 f"fontSize={FONT_LABEL};verticalLabelPosition=bottom;verticalAlign=top;labelBackgroundColor=#ffffff;")
        self.add(id_, parent, value, style, x, y, w, h)

    def note(self, id_, parent, value, x, y, w, h, font_size=10, color="#555555", align="left"):
        style = f"text;html=1;align={align};verticalAlign=top;fontSize={font_size};fontColor={color};whiteSpace=wrap;"
        self.add(id_, parent, value, style, x, y, w, h)

    def cloud_shape(self, id_, parent, value, x, y, w, h):
        self.add(id_, parent, value, "ellipse;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;", x, y, w, h)

    def title(self, id_, text, x, y, w=520, h=48, subtitle=""):
        """캔버스 상단 제목/범위 블록 (050-readability-standard.md).

        text: 굵은 대제목(예: "his-infra Production"), subtitle: 작은 부제(예:
        "AWS · ap-northeast-2 · 3-Tier"). 보는 사람이 "무엇을·어디를" 즉시 파악하게 한다.
        """
        val = text
        if subtitle:
            val = (f'{text}<br><span style="font-size:12px;font-weight:normal;'
                   f'color:#555555;">{subtitle}</span>')
        style = (f"text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;"
                 f"fontSize={FONT_TITLE};fontStyle=1;fontColor=#232F3E;whiteSpace=wrap;")
        self.add(id_, "1", val, style, x, y, w, h)

    def legend(self, id_, x, y, entries, title="범례 (Legend)"):
        """색상/선 종류 범례 박스 (050-readability-standard.md).

        entries: [(kind, color, label), ...]
          kind='box'  → 컨테이너 테두리색 스와치(빈 사각형 + 색 테두리): VPC/Subnet/Region/ASG 구분
          kind='line' → 실선 엣지 스와치: 실제 트래픽/데이터 경로
          kind='dash' → 점선 엣지 스와치: 논리적 연결(DNS/로그/동기화 등)
        범례 박스는 swimlane이 아니므로 010 §4 팔레트 검사 대상이 아니다(회색 테두리 허용).
        빈 공간(캔버스 우상단/우하단 등)에 배치해 다른 컨테이너와 겹치지 않게 하십시오.
        """
        row_h, header_h, w = 24, 34, 232
        h = header_h + len(entries) * row_h + 10
        box_style = ("rounded=0;whiteSpace=wrap;html=1;fillColor=#ffffff;strokeColor=#666666;"
                     "verticalAlign=top;align=left;fontStyle=1;fontSize=12;fontColor=#333333;"
                     "spacingLeft=10;spacingTop=8;")
        self.add(id_, "1", title, box_style, x, y, w, h)
        for i, (kind, color, label) in enumerate(entries):
            sy = header_h + i * row_h
            if kind == "box":
                sw = f"rounded=0;html=1;fillColor=none;strokeColor={color};strokeWidth=2;"
                self.add(f"{id_}_sw{i}", id_, "", sw, 12, sy, 30, 16)
            else:
                sw = (f"shape=line;html=1;strokeColor={color};strokeWidth=2;"
                      + ("dashed=1;" if kind == "dash" else ""))
                self.add(f"{id_}_sw{i}", id_, "", sw, 12, sy + 6, 30, 4)
            lb = ("text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;"
                  "fontSize=11;fontColor=#333333;whiteSpace=wrap;")
            self.add(f"{id_}_lb{i}", id_, label, lb, 50, sy, w - 58, 16)

    def to_xml(self, diagram_name="Architecture"):
        # diagram_name 도 반드시 esc 를 거쳐야 한다. add()/edge() 는 모든 속성을 통과시키는데
        # 정작 여기만 날것으로 보간하고 있었다. 다이어그램 이름에 & 나 " 가 들어가는 것은
        # 아주 흔한데("VPC & Subnet 구성", "Dev \"Prod\" 비교"), 그러면 add() 주석이 적어 둔
        # 바로 그 사고가 재현된다 — .drawio 파일 전체가 XML 파싱 불가가 되어 draw.io 가
        # 열지 못한다(실측: & / " / < 세 경우 모두 ET.fromstring 이 not well-formed 로 실패).
        return f'''<mxfile host="app.diagrams.net" agent="Mozilla/5.0">
  <diagram id="arch" name="{esc(diagram_name)}">
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
def _abs_geom(cells, cid, _seen=None):
    """cid의 부모 체인을 따라가며 절대 좌표 (x, y, w, h)를 계산한다.

    부모 체인이 순환하거나(A→B→A) mxGeometry 가 없는 셀을 만나면 RecursionError /
    AttributeError 로 이 함수가 크래시할 수 있다. 호출자인 validate() 에는 예외
    처리가 없어 검증기 자체가 스택트레이스로 죽으면, 종료 코드가 "위반 발견"과
    구분되지 않아 [FAIL] 판정을 통째로 삼킨다.
    """
    if cid in ("0", "1", None) or cid not in cells:
        return 0.0, 0.0, 0.0, 0.0
    # 순환 참조 차단. 손으로 편집한 XML 이나 생성 스크립트 버그로 실제로 만들어질 수 있고,
    # 그 자체는 별도 검사가 잡을 문제이지 좌표 계산이 죽을 이유는 아니다.
    if _seen is None:
        _seen = set()
    if cid in _seen:
        return 0.0, 0.0, 0.0, 0.0
    _seen.add(cid)
    c = cells[cid]
    g = c.find("mxGeometry")
    if g is None:
        # geometry 없는 셀(그룹 래퍼 등)은 자체 크기를 0으로 보되 부모 오프셋은 계승한다.
        px, py, _, _ = _abs_geom(cells, c.get("parent"), _seen)
        return px, py, 0.0, 0.0
    # 속성이 빈 문자열인 경우까지 흡수한다. float("") 는 ValueError 다.
    x, y = float(g.get("x") or 0), float(g.get("y") or 0)
    w, h = float(g.get("width") or 0), float(g.get("height") or 0)
    px, py, _, _ = _abs_geom(cells, c.get("parent"), _seen)
    return x + px, y + py, w, h


def _style_val(style, key, default):
    """drawio style 문자열에서 key= 값을 뽑는다. 없으면 default.

    값이 "none" 이어도 그대로 돌려준다. 예전에는 "none" 을 default 로 치환했는데,
    strokeColor=none(테두리 없음을 명시한 아이콘)이 미리보기에서 검은 테두리로 그려져
    실제 drawio 렌더링과 달라졌다. matplotlib 은 "none" 을 그대로 받으므로 치환할 이유가 없다.
    """
    for part in style.split(";"):
        if part.startswith(key + "="):
            return part.split("=", 1)[1]
    return default


def _edge_label_pos(pts):
    """엣지 폴리라인의 점 목록 → 라벨을 놓을 (x, y).

    예전에는 pts[len(pts)//2] 를 그대로 썼다. 점이 짝수일 때 그 인덱스는 가운데가 아니라
    뒤쪽 점이고, 특히 waypoint 없는 엣지(점 2개 = 출발/도착 중심)에서는 곧 "도착점"이라
    라벨이 타깃 도형 위에 겹쳐 찍혔다. edge() 에 points 를 넘기는 것은 장거리 엣지용
    예외 경로라 실제로는 대부분의 엣지가 이 경우에 해당했고, 한 노드로 여러 엣지가
    들어오면 라벨이 그 자리에 포개졌다. 짝수면 가운데 선분의 중점을 쓴다.
    """
    half = len(pts) // 2
    if len(pts) % 2 == 0:
        p1, p2 = pts[half - 1], pts[half]
        return (p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2
    return pts[half]


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

    # 090 §1 은 "XML 이 파싱 에러 없이 로드됨"을 완료 조건 1번으로 규정한다. 그런데 예전에는
    # 이 검사만 [FAIL] 항목이 아니라 ParseError 트레이스백으로 빠져나가, 나머지 두 조건
    # (ID 중복/끊어진 참조)과 보고 형식이 갈렸다. 검증기가 예외로 죽는 것과 위반을 검출한
    # 것을 호출자가 구분할 수 없게 되는 구조라, 파싱 실패도 다른 위반과 같은 형식으로 낸다.
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        return False, (f"[FAIL] XML 파싱 실패 (090 §1 완료 조건 1번): {e}\n"
                       f"    닫히지 않은 태그나 잘못된 문자가 없는지 확인하십시오. "
                       f"XML 속성값에는 <, & 를 그대로 넣을 수 없습니다(esc() 를 쓰십시오).")
    # 중복 ID 검사는 반드시 원본 순서 목록에서 세야 한다. dict 로 먼저 접으면 중복 키가
    # 합쳐져 090 §1 항목 2("모든 mxCell id 중복 없음")가 영구히 통과해버린다.
    raw_cells = [c for c in root.findall(".//mxCell") if c.get("id")]
    cells = {c.get("id"): c for c in raw_cells}
    lines = []

    ids = [c.get("id") for c in raw_cells]
    dup = [i for i in ids if ids.count(i) > 1]
    if dup:
        lines.append(f"[FAIL] 중복 ID: {sorted(set(dup))}")
    idset = set(ids)
    # cells(중복 제거된 dict)가 아니라 raw_cells 를 훑는다. 같은 id 가 여러 번 나오면 dict 에는
    # 마지막 셀만 남아, 앞선 동명 셀에 달린 끊어진 참조가 검사에서 빠진다.
    missing = [(c.get("id"), a, c.get(a)) for c in raw_cells
               for a in ("source", "target") if c.get(a) and c.get(a) not in idset]
    if missing:
        lines.append(f"[FAIL] 끊어진 참조: {missing}")

    # 엣지 끝점 미연결 검사 — drawio 에서 선을 드래그하다 도형에서 떨어지면 source/target
    # 속성 자체가 사라지고 mxGeometry 안에 sourcePoint/targetPoint 고정 좌표만 남는다.
    # 위 "끊어진 참조" 검사는 속성에 적힌 ID의 존재 여부만 보므로 속성이 아예 없는 이 경우를
    # 통과시킨다. 눈으로는 붙어 보이지만(몇 px 차이) 도형을 옮기면 화살표가 따라가지
    # 않으므로 완료 조건에 포함한다.
    detached = []
    for cid, c in cells.items():
        if c.get("edge") != "1":
            continue
        geom = c.find("mxGeometry")
        pts = {p.get("as") for p in (geom.findall("mxPoint") if geom is not None else [])}
        for attr, pt in (("source", "sourcePoint"), ("target", "targetPoint")):
            if not c.get(attr):
                where = f"고정좌표 {pt}" if pt in pts else "끝점 정의 없음"
                detached.append(f"{cid}.{attr}({where})")
    if detached:
        lines.append(f"[FAIL] 엣지 끝점 미연결(도형에 부착되지 않음): {detached}")

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
    # row_height()/uniform_row()로 통일 높이를 계산해놓고 실제 컨테이너 height
    # 인자에는 반영하지 않으면 바닥선이 어긋나는 회귀가 생긴다. 같은 parent 밑에서
    # y좌표(행 시작선)가 사실상 같은데 height가 다른 swimlane 형제가 있으면,
    # uniform_row() 적용을 빠뜨린 것으로 보고 경고한다.
    EPS = 2.0
    for parent, kids in siblings.items():
        containers = [k for k in kids if "swimlane" in cells[k].get("style", "")]
        # y 를 EPS 단위로 반올림해 버킷팅하면 경계에서 갈린다: y=2.9 는 버킷 2.0, y=3.1 은
        # 버킷 4.0 이라 0.2px 차이인 형제가 서로 다른 행으로 판정된다. 정렬한 뒤 행의 첫
        # 원소를 기준으로 EPS 이내를 같은 행으로 묶어 그 경계 인위성을 없앤다.
        measured = sorted((abs_pos(k)[1], abs_pos(k)[3], k) for k in containers)
        rows = []
        for y, h, k in measured:
            if rows and y - rows[-1][0] <= EPS:
                rows[-1][1].append((k, h))
            else:
                rows.append((y, [(k, h)]))
        for y, items in rows:
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
    # 예시에 그대로 나오는 표준 라벨까지 매번 걸리면 경고가 무의미해진다. 진짜 겹침
    # 위험이 있는 문장형 서브라벨(함수명 나열 등)만 잡히도록 여유를 크게 둔다.
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
        # OpenStack 공식 강조색 3종 (035 §0). OpenStack 다이어그램에서 컨테이너를 구분해야
        # 할 때는 AWS 유래 색이 아니라 이쪽을 쓴다 — 공식 표준이 "bright primary colors,
        # such as light blue, red, or green"만 허용하므로 회색 계열은 원칙적으로 부적합하다.
        "#4A90D9",  # light blue
        "#DA1A32",  # red
        "#2E7D32",  # green
    }
    container_strokes = set()
    for cid, c in cells.items():
        style = c.get("style", "")
        if "swimlane" not in style:
            continue
        m = re.search(r"strokeColor=(#[0-9A-Fa-f]{6})", style)
        if not m:
            continue
        container_strokes.add(m.group(1).upper())
        if m.group(1).upper() not in APPROVED_CONTAINER_COLORS:
            color_violations.append((cid, m.group(1)))
            lines.append(f"[FAIL] 컨테이너 팔레트 위반 (010 §4): id={cid} strokeColor={m.group(1)} "
                         f"(허용값: {sorted(APPROVED_CONTAINER_COLORS)})")

    # OpenStack 다이어그램 전용 컨테이너 색상 검사 (035 §0, 010 §4보다 우선 — 010:95).
    # 위 010 §4 검사는 회색(#888888/#555555)을 "팀 컨벤션 예외"로 허용하지만, OpenStack
    # 공식 표준은 "bright primary colors, such as light blue, red, or green"만 허용하여
    # 회색 계열이 원천 불가함(openstack-basic 논리 아키텍처에서 #888888 적발 실사례).
    # native 스텐실(mxgraph.openstack.*) 또는 openstack_icon() 강조색 사용 여부로 OpenStack
    # 다이어그램인지 판별해, 해당 시에만 010 §4보다 더 엄격한 3원색 기준을 추가 적용한다.
    #
    # 판별 신호를 두 갈래로 나눈다. 예전에는 스텐실 경로와 강조색 3종을 한 묶음으로 놓고
    # "아무 셀의 style 문자열에 들어 있으면 OpenStack"으로 봤는데, 강조색은 컨테이너
    # 테두리뿐 아니라 아이콘 fillColor·폰트색·엣지색에도 정당하게 쓰인다. 그래서 AWS
    # 다이어그램에 빨간 도형(fillColor=#DA1A32) 하나만 있어도 전체가 OpenStack으로 분류되고,
    # 바로 위 010 §4가 승인한 AWS 표준 색(#147E40 VPC, #007CBC Subnet)이 전부 위반으로
    # 걸려 정상 다이어그램이 하드 FAIL 났다(실측 재현). 색상 검사 자체가 swimlane에만
    # 적용되므로 아이콘 색은 애초에 자유인데 그 자유가 판별자를 뒤집던 셈이다.
    #   - mxgraph.openstack.* 스텐실: 어떤 셀에 있든 OpenStack 다이어그램의 확실한 증거
    #   - 강조색 3종: 컨테이너(swimlane) 테두리로 쓰인 경우에만 신호로 인정
    OPENSTACK_STENCIL_MARKER = "mxgraph.openstack."
    OPENSTACK_EMPHASIS_COLORS = {"#4A90D9", "#DA1A32", "#2E7D32"}
    is_openstack_diagram = (
        any(OPENSTACK_STENCIL_MARKER in c.get("style", "") for c in cells.values())
        or bool(container_strokes & OPENSTACK_EMPHASIS_COLORS)
    )
    if is_openstack_diagram:
        OPENSTACK_ALLOWED_CONTAINER_COLORS = {"#000000", "#4A90D9", "#DA1A32", "#2E7D32"}
        for cid, c in cells.items():
            style = c.get("style", "")
            if "swimlane" not in style:
                continue
            m = re.search(r"strokeColor=(#[0-9A-Fa-f]{6})", style)
            if m and m.group(1).upper() not in OPENSTACK_ALLOWED_CONTAINER_COLORS and (cid, m.group(1)) not in color_violations:
                color_violations.append((cid, m.group(1)))
                lines.append(f"[FAIL] OpenStack 컨테이너 색상 위반 (035 §0, 010 §4보다 우선): id={cid} strokeColor={m.group(1)} "
                             f"(허용값: 검정 기본 또는 밝은 원색 3종 #4A90D9/#DA1A32/#2E7D32)")

    # 범례(Legend) 누락 휴리스틱 (050-readability-standard.md §1) — WARN only, ok에 영향 없음.
    # 컨테이너 색이 2종 이상이거나 실선+점선 엣지가 함께 쓰였는데 '범례/Legend' 라벨 셀이
    # 하나도 없으면, 보는 사람이 색·선의 의미를 추측해야 하므로 범례 누락을 경고한다.
    # legend()의 스와치는 swimlane도 edge도 아니라 아래 카운팅에 오탐으로 잡히지 않는다.
    container_colors = set()
    has_solid_edge = has_dashed_edge = has_legend = False
    for cid, c in cells.items():
        style = c.get("style", "")
        if re.search(r"범례|legend", c.get("value", "") or "", re.I):
            has_legend = True
        if "swimlane" in style:
            m = re.search(r"strokeColor=(#[0-9A-Fa-f]{6})", style)
            if m:
                container_colors.add(m.group(1).upper())
        elif c.get("edge") == "1":
            if "dashed=1" in style:
                has_dashed_edge = True
            else:
                has_solid_edge = True
    if not has_legend and (len(container_colors) >= 2 or (has_solid_edge and has_dashed_edge)):
        reasons = []
        if len(container_colors) >= 2:
            reasons.append(f"컨테이너 색 {len(container_colors)}종")
        if has_solid_edge and has_dashed_edge:
            reasons.append("실선+점선 엣지 혼용")
        lines.append(f"[WARN] 범례 누락 의심 ({', '.join(reasons)}인데 '범례/Legend' 셀 없음) "
                     f"— layout_toolkit.legend()로 색·선 의미를 표기하십시오 (050 §1)")

    ok = not dup and not missing and not detached and not color_violations
    if ok and not lines:
        lines.append(f"[OK] {len(ids)}개 mxCell, 중복/끊어진 참조/끝점 미연결/형제 겹침/라벨폭/팔레트 위반 없음")
    return ok, "\n".join(lines)


# ────────────────────────────────────────────────────────────────
# 엣지 포함 간이 렌더링 (015 §5 "생성 직후 렌더링 검증"의 실제 구현체)
# ────────────────────────────────────────────────────────────────
def _register_korean_font():
    """미리보기 PNG에서 한글 라벨/범례/제목이 네모(□)로 깨지지 않도록 한글 지원 폰트를 등록한다.

    render_preview 육안 검증은 이 스킬의 필수 완료 조건인데, 라벨이 전부 한글이라
    matplotlib 기본 폰트(DejaVu Sans)로는 텍스트가 전부 □로 나와 텍스트 겹침/줄바꿈을
    검증할 수 없었다(매 실행 글리프 경고 40줄 스팸도 발생). 리눅스 네이티브 폰트를 우선
    찾고, 없으면 WSL의 Windows 폰트를 폴백으로 쓴다. 어느 것도 없으면 None을 반환한다.
    """
    import os
    from matplotlib import font_manager as fm
    import matplotlib.pyplot as plt

    candidates = [
        "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",       # apt: fonts-nanum
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",  # apt: fonts-noto-cjk
        os.path.expanduser("~/.local/share/fonts/NanumGothic.ttf"),
        os.path.expanduser("~/.fonts/NanumGothic.ttf"),
        "/mnt/c/Windows/Fonts/malgun.ttf",        # WSL 폴백: 맑은 고딕(정적, 굵기 정상)
        "/mnt/c/Windows/Fonts/NotoSansKR-VF.ttf",  # WSL 폴백: Noto Sans KR(가변)
    ]
    for fpath in candidates:
        if not os.path.exists(fpath):
            continue
        try:
            fm.fontManager.addfont(fpath)
            name = fm.FontProperties(fname=fpath).get_name()
            plt.rcParams["font.family"] = name
            plt.rcParams["axes.unicode_minus"] = False
            return name
        except Exception:
            continue
    return None


def render_preview(path, out_png):
    """컨테이너/아이콘 사각형 + 엣지(연결선, waypoint 포함)까지 그린 PNG를 저장한다.

    다이어그램 생성 스크립트마다 박스만 그리는 임시 렌더러를 매번 새로 짜면, 엣지
    라우팅이 다른 컨테이너를 뚫고 지나가는지 등을 육안 검증하지 못하는 구멍이 생긴다.
    Read 도구로 이 PNG를 열어 박스 정렬뿐 아니라 연결선 경로까지 확인한 뒤에만
    완료를 선언하십시오.
    """
    import html as _html
    import logging
    import re
    import warnings
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import matplotlib.patches as patches
    import xml.etree.ElementTree as ET

    # 한글 폰트 등록 + findfont 경고(가변폰트 weight 등) 소음 억제
    logging.getLogger("matplotlib.font_manager").setLevel(logging.ERROR)
    kfont = _register_korean_font()
    if kfont:
        print(f"[INFO] 미리보기 한글 폰트: {kfont}")
    else:
        print("[INFO] 한글 지원 폰트를 찾지 못해 미리보기의 한글 라벨이 □로 표시됩니다. "
              "'sudo apt install fonts-nanum' 후 재실행하면 라벨까지 육안 검증됩니다.")

    root = ET.parse(path).getroot()
    cells = {c.get("id"): c for c in root.findall(".//mxCell") if c.get("id")}

    fig, ax = plt.subplots(figsize=(24, 14))
    maxx = maxy = 0.0

    for cid, c in cells.items():
        if cid in ("0", "1") or c.get("vertex") != "1":
            continue
        x, y, w, h = _abs_geom(cells, cid)
        style = c.get("style", "")
        is_container = "swimlane" in style
        # 값 추출은 모듈 레벨 _style_val 로 옮겼다(순수 함수라 회귀 테스트가 가능해진다).
        fill = _style_val(style, "fillColor", "none")
        stroke = _style_val(style, "strokeColor", "black")
        rect = patches.Rectangle((x, -y - h), w, h,
                                  linewidth=1.8 if is_container else 0.8, edgecolor=stroke,
                                  facecolor=fill, alpha=0.5 if is_container else 0.85)
        ax.add_patch(rect)
        # validate() 의 plain_lines() 와 같은 정규식을 쓴다. `.split("<br>")` 로만 자르면
        # `<br/>` 형태를 놓쳐 미리보기 라벨에 태그가 그대로 찍히고, 육안 검증 대상인 그림이
        # 실제 렌더링과 달라진다.
        label = re.split(r"<br\s*/?>", c.get("value") or "")[0]
        label = _html.unescape(re.sub(r"<[^>]+>", "", label)).strip()
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
            mx, my = _edge_label_pos(pts)
            ax.text(mx, my, val, fontsize=6.5, color="#333333",
                    bbox=dict(facecolor="white", edgecolor="none", pad=0.5), zorder=6)

    ax.set_xlim(-20, maxx + 20)
    ax.set_ylim(-maxy - 20, 20)
    ax.set_aspect("equal")
    ax.axis("off")
    # 한글 폰트를 못 찾은 경우의 글리프 누락 UserWarning이 40줄씩 스팸되지 않도록 억제
    # (누락 사실은 위 [INFO] 한 줄로 이미 안내함). 폰트가 있으면 애초에 경고가 없다.
    with warnings.catch_warnings():
        warnings.filterwarnings("ignore", category=UserWarning)
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
    import urllib.error
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
                # urlopen 은 4xx/5xx 를 HTTPError 로 올리므로 이 분기는 평소 도달하지 않는다.
                # 리다이렉트 처리기가 상태 코드를 그대로 돌려주는 경우에 대비해 남겨 둔다.
                if resp.status >= 400:
                    lines.append(f"[WARN] 아이콘 URL 응답 이상 (status={resp.status}): {url}")
        except urllib.error.HTTPError as e:
            # HTTPError 를 아래 일반 except 에 맡기면 "죽은 링크"가 "네트워크 확인 불가"로
            # 강등되어, 문서(090 §7, 015)가 약속한 [WARN] 판정이 한 번도 나오지 않는다.
            # 이 검사의 목적 자체가 URL 생존 확인이므로 두 경우를 반드시 갈라야 한다.
            lines.append(f"[WARN] 아이콘 URL 응답 이상 (status={e.code}): {url}")
        except Exception as e:
            lines.append(f"[INFO] 아이콘 URL 확인 불가(네트워크/타임아웃, FAIL 아님): {url} ({e.__class__.__name__})")
    if not lines:
        lines.append(f"[OK] 서드파티 아이콘 URL {len(urls)}개 모두 응답 정상")
    return "\n".join(lines)


if __name__ == "__main__":
    import os
    import sys
    if len(sys.argv) != 2:
        print("usage: python3 layout_toolkit.py <path-to.drawio>")
        raise SystemExit(1)
    if not os.path.isfile(sys.argv[1]):
        print(f"[ERROR] 파일을 찾을 수 없습니다: {sys.argv[1]}")
        raise SystemExit(1)
    ok, report = validate(sys.argv[1])
    print(report)
    # 미리보기는 육안 검증 보조이지 판정 근거가 아니다. matplotlib 은 이 저장소의 어떤 설치
    # 경로(mise config.toml, bootstrap.sh/ansible)에도 선언되어 있지 않아 신규 환경에는 없다.
    # 그 ImportError 가 아래 SystemExit 앞에서 그대로 터지면, 검증을 통과한 파일과 위반한
    # 파일이 똑같이 exit 1 로 끝나 090 §2~3 이 요구하는 기계 판정이 무의미해진다. 렌더링
    # 실패는 안내로 낮추고 판정은 validate() 결과로만 낸다.
    preview_path = sys.argv[1].rsplit(".", 1)[0] + "-preview.png"
    try:
        render_preview(sys.argv[1], preview_path)
        print(f"[INFO] 엣지 포함 렌더링 미리보기 저장: {preview_path}")
    except ImportError:
        print("[INFO] matplotlib 이 없어 미리보기를 건너뜁니다(검증 판정에는 영향 없음). "
              "육안 검증까지 하려면: pip install matplotlib")
    except Exception as e:
        print(f"[WARN] 미리보기 생성 실패({e.__class__.__name__}: {e}) — 검증 판정에는 영향 없음")
    raise SystemExit(0 if ok else 1)
