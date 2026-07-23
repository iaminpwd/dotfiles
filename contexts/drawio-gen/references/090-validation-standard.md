---
role: Infrastructure Diagram Generator
priority: high
trigger: drawio XML 생성 직후, 완료 선언 전 검증 단계에서 적용
references:
  - contexts/drawio-gen/references/010-drawio-xml-standard.md
reviewed: 2026-07-23
---
# 검증 및 수락 기준 (Success Criteria)

## 1. 완료 조건 (Done when)

- **[MUST]** 아래를 모두 통과해야 완료로 간주하십시오.
  1. XML이 파싱 에러 없이 로드됨
  2. 모든 `mxCell id` 중복 없음
  3. 모든 edge의 `source`/`target`이 실제 존재하는 노드 id를 가리킴 (끊어진 참조 없음)

## 2. 검증 도구 매핑

- **[MUST]** XML 작성 직후 아래 스크립트로 위 1~3을 기계적으로 검증하고, 실패 시 원인을 수정한 뒤 재검증하십시오.

```python
import xml.etree.ElementTree as ET
cells = ET.parse("{파일경로}").getroot().findall(".//mxCell")
ids = [c.get("id") for c in cells if c.get("id")]
assert len(ids) == len(set(ids)), "중복 ID 존재"
idset = set(ids)
missing = [(c.get("id"), a, c.get(a)) for c in cells for a in ("source", "target") if c.get(a) and c.get(a) not in idset]
assert not missing, f"끊어진 참조: {missing}"
```

- **[PREFER]** 위 스니펫을 매번 새로 타이핑하지 말고 `contexts/drawio-gen/scripts/layout_toolkit.py`의 `validate(path)`를 호출하십시오. 동일한 1~3 검증에 더해 형제 노드 간 사각형 겹침 검사(010 §10)와 **컨테이너 색상 팔레트 준수 검사(010 §4)**까지 한 번에 수행합니다. 색상 검사는 swimlane 컨테이너의 `strokeColor`가 010 §4 표에 정의된 값 목록에 있는지 기계적으로 대조하며, VPC/Subnet 등에 팔레트에 없는 임의 색상(예: `#8C4FFF`)을 쓰는 것을 사람이 매번 표와 대조하지 않아도 자동으로 잡아냅니다.

```bash
python3 contexts/drawio-gen/scripts/layout_toolkit.py {파일경로}
```

## 3. 레이아웃 품질 검증 (겹침/정렬/여백)

- **[MUST]** ID/참조 무결성만으로는 "보기 좋은 다이어그램"이 보장되지 않습니다. 010 §10(레이아웃 계산 원칙)에 따라 생성했는지 아래도 함께 확인하십시오.
  1. `layout_toolkit.validate()`의 형제 겹침 경고가 0건인지 (Internet 클라우드가 Cloud 컨테이너 상단 경계에 걸치는 등 의도된 디자인 오버랩은 예외)
  2. 같은 행에 배치된 형제 컨테이너들의 `height`가 서로 동일한지 — `validate()`가 `[WARN] 행 높이 불일치`로 자동 감지합니다. 서브넷처럼 촘촘하게 나열되어 시각적으로 "한 행"으로 읽히는 형제 사이의 불일치만 실제 결함으로 간주해 `uniform_row()`로 수정하십시오. VPC1 대 VPC2처럼 서로 다른 개별 대형 블록으로 명확히 구분되는 최상위 컨테이너 쌍은 높이가 달라도 정상(원본 his-infra 다이어그램도 VPC1=513/VPC2=613으로 의도적으로 다름)이므로, 이 경우의 경고는 예외로 판단해도 됩니다.
  3. 컨테이너의 선언된 크기가 실제 콘텐츠 바운딩박스보다 과도하게 크지 않은지(불필요한 빈 공간)
  4. `layout_toolkit.render_preview(path, out_png)`로 **엣지(연결선)까지 포함된** PNG를 생성해 Read 도구로 실제로 열어 육안 확인하십시오. 박스만 그리는 임시 렌더러를 매번 새로 짜면 엣지 라우팅이 다른 서브넷을 뚫고 지나가는 문제를 못 잡습니다(2026-07-22, his-infra 작업에서 `edge_nat_igw`가 waypoint 없이 VPC1 전체를 대각선으로 가로지른 사례). 장거리 엣지가 서브넷 내부를 지나간다면 010 §10 "장거리 엣지는 waypoint로 경로 고정" 규칙에 따라 빈 공간(형제 컨테이너 사이 gap, 행과 행 사이 gap 등)을 지나도록 waypoint를 다시 계산하십시오.
  5. 아이콘 라벨에 `validate()`가 `[WARN] 라벨 폭 초과 의심`을 보고하면, 서브라벨 문장을 줄이거나 여러 `<br>` 줄로 나눠 재검증하십시오.
  6. `validate()`가 `[WARN] 범례 누락 의심`(컨테이너 색 2종 이상 또는 실선+점선 엣지 혼용인데 범례 셀 없음)을 보고하면, `layout_toolkit.legend()`로 색·선 의미 범례를 추가하십시오(050 §1). 렌더링 PNG는 `render_preview()`가 한글 폰트를 자동 등록하므로 범례·라벨의 한글 텍스트까지 육안 검증됩니다(폰트 미발견 시 `[INFO]`로 설치 안내).
  7. 서드파티 아이콘을 썼다면 네트워크가 가능한 환경에서 `layout_toolkit.check_icon_urls(path)`로 이미지 URL이 살아있는지 확인하십시오. 네트워크 불가/타임아웃은 `[INFO]`로만 표시되며 완료 조건을 막지 않습니다.
