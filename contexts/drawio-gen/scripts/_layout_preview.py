"""Optional matplotlib preview rendering for draw.io diagrams.

Importing this module never imports matplotlib; only render_preview() does.
"""

from _layout_geometry import _abs_geom, _style_val, _edge_label_pos


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
