"""Shared draw.io geometry calculations for validation and previews.

The public API is re-exported from layout_toolkit.py.
"""

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
