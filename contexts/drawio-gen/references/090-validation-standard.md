---
role: Infrastructure Diagram Generator
priority: high
trigger: drawio XML 생성 직후, 완료 선언 전 검증 단계에서 적용
references:
  - contexts/drawio-gen/references/010-drawio-xml-standard.md
---
# 검증 및 수락 기준 (Success Criteria)

## 1. 완료 조건 (Done when)

- **[MUST]** 아래를 모두 통과해야 완료로 간주할 것.
  1. XML이 파싱 에러 없이 로드됨
  2. 모든 `mxCell id` 중복 없음
  3. 모든 edge의 `source`/`target`이 실제 존재하는 노드 id를 가리킴 (끊어진 참조 없음)
  4. 모든 edge가 `source`/`target` **속성 자체를 갖고 있음** (끝점 미연결 없음). drawio에서 선을 드래그하다 도형에서 떨어지면 속성이 통째로 사라지고 `mxGeometry` 안에 `sourcePoint`/`targetPoint` 고정 좌표만 남는다. 3번 검사는 "속성에 적힌 id가 존재하는가"만 보므로 이 경우를 통과시킨다 — openstack-basic 개념 아키텍처에서 "UI 제공" 화살표가 구분선에서 2.33px 떨어진 채 `[OK]`로 보고된 실사례가 있다. 눈으로는 붙어 보이지만 도형을 옮기면 화살표가 따라가지 않으므로 완료 조건에 포함한다.

## 2. 검증 도구 매핑

- **[MUST]** XML 작성 직후 아래 스크립트로 위 1~3을 기계적으로 검증하고, 실패 시 원인을 수정한 뒤 재검증할 것.

```python
import xml.etree.ElementTree as ET
cells = ET.parse("{파일경로}").getroot().findall(".//mxCell")
ids = [c.get("id") for c in cells if c.get("id")]
assert len(ids) == len(set(ids)), "중복 ID 존재"
idset = set(ids)
missing = [(c.get("id"), a, c.get(a)) for c in cells for a in ("source", "target") if c.get(a) and c.get(a) not in idset]
assert not missing, f"끊어진 참조: {missing}"
```

- **[PREFER]** 위 스니펫을 매번 새로 타이핑하는 대신 `scripts/layout_toolkit.py`의 `validate(path)`를 호출할 것. 동일한 1~3 검증에 더해 형제 노드 간 사각형 겹침 검사(015)와 **컨테이너 색상 팔레트 준수 검사(010 §4)**까지 한 번에 수행함. 색상 검사는 swimlane 컨테이너의 `strokeColor`가 010 §4 표에 정의된 값 목록에 있는지 기계적으로 대조하며, VPC/Subnet 등에 팔레트에 없는 임의 색상(예: `#8C4FFF`)을 쓰는 것을 사람이 매번 표와 대조하지 않아도 자동으로 잡아냅니다. native 스텐실(`mxgraph.openstack.*`) 또는 `openstack_icon()` 강조색이 감지되면 OpenStack 다이어그램으로 판별하여, 010 §4보다 우선하는 035 §0의 엄격한 3원색 컨테이너 규칙(회색 계열 불허)을 추가로 검사합니다.

```bash
python3 scripts/layout_toolkit.py {파일경로}
# 종료 코드가 판정임: 0=통과, 1=위반. 미리보기 PNG 는 matplotlib 이 있을 때만 함께
# 생성되며, 없으면 [INFO] 안내 후 검증만 수행합니다(판정에는 영향 없음).
```

- **[MUST] 검증기를 수정하면 회귀 테스트를 먼저 통과시키십시오**: `layout_toolkit.py`의 `validate()`를 고칠 때는 아래를 실행해 기존 검사가 조용히 죽지 않았는지 확인할 것. 각 픽스처는 이 문서와 010의 규칙이 만들어진 실제 실패 사례를 재현함. 새 검사를 추가하면 그 검사를 유발하는 픽스처와 `run.sh`의 기대 결과도 함께 추가할 것.

```bash
bash contexts/drawio-gen/tests/run.sh
```

## 3. 레이아웃 품질 검증 (겹침/정렬/여백)

- **[MUST]** ID/참조 무결성만으로는 "보기 좋은 다이어그램"이 보장되지 않습니다. 015(레이아웃 계산 원칙)에 따라 생성했는지 아래도 함께 확인할 것.
  1. `layout_toolkit.validate()`의 형제 겹침 경고가 0건인지 (Internet 클라우드가 Cloud 컨테이너 상단 경계에 걸치는 등 의도된 디자인 오버랩은 예외)
  2. 같은 행에 배치된 형제 컨테이너들의 `height`가 서로 동일한지 — `validate()`가 `[WARN] 행 높이 불일치`로 자동 감지함. 서브넷처럼 촘촘하게 나열되어 시각적으로 "한 행"으로 읽히는 형제 사이의 불일치만 실제 결함으로 간주해 `uniform_row()`로 수정할 것. VPC1 대 VPC2처럼 서로 다른 개별 대형 블록으로 명확히 구분되는 최상위 컨테이너 쌍은 높이가 달라도 정상(원본 his-infra 다이어그램도 VPC1=513/VPC2=613으로 의도적으로 다름)이므로, 이 경우의 경고는 예외로 판단해도 됩니다.
  3. 컨테이너의 선언된 크기가 실제 콘텐츠 바운딩박스보다 과도하게 크지 않은지(불필요한 빈 공간)
  4. `layout_toolkit.render_preview(path, out_png)`로 **엣지(연결선)까지 포함된** PNG를 생성해 실제로 열어 육안 확인할 것. 박스만 그리는 임시 렌더러를 매번 새로 짜면 엣지 라우팅이 다른 서브넷을 뚫고 지나가는 문제를 못 잡습니다. 장거리 엣지가 서브넷 내부를 지나간다면 015 §4 "장거리 엣지는 waypoint로 경로 고정" 규칙에 따라 빈 공간(형제 컨테이너 사이 gap, 행과 행 사이 gap 등)을 지나도록 waypoint를 다시 계산할 것.
  5. 아이콘 라벨에 `validate()`가 `[WARN] 라벨 폭 초과 의심`을 보고하면, 서브라벨 문장을 줄이거나 여러 `<br>` 줄로 나눠 재검증할 것.
  6. `validate()`가 `[WARN] 범례 누락 의심`(컨테이너 색 2종 이상 또는 실선+점선 엣지 혼용인데 범례 셀 없음)을 보고하면, `layout_toolkit.legend()`로 색·선 의미 범례를 추가할 것(050 §1). 렌더링 PNG는 `render_preview()`가 한글 폰트를 자동 등록하므로 범례·라벨의 한글 텍스트까지 육안 검증됩니다(폰트 미발견 시 `[INFO]`로 설치 안내).
  7. 서드파티 아이콘을 썼다면 네트워크가 가능한 환경에서 `layout_toolkit.check_icon_urls(path)`로 이미지 URL이 살아있는지 확인할 것. 네트워크 불가/타임아웃은 `[INFO]`로만 표시되며 완료 조건을 막지 않습니다.
