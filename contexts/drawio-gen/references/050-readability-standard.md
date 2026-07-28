---
role: Infrastructure Diagram Generator
priority: high
trigger: drawio XML 생성 시 "읽는 사람"의 가독성(범례/제목/라벨/타이포그래피)을 확보할 때 적용
references:
  - contexts/drawio-gen/references/010-drawio-xml-standard.md
---
# 다이어그램 가독성 표준 (Reader-Facing Readability)

015가 "박스가 겹치지 않게"(배치 정합성)를 다룬다면, 본 모듈은 **다이어그램을 처음 보는 사람이 의미를 즉시 파악**하도록 만드는 규칙입니다. 메커니즘은 전부 `~/dotfiles/contexts/drawio-gen/scripts/layout_toolkit.py`에 구현되어 있으니 매번 새로 짜지 말고 헬퍼를 호출하십시오.

## 1. 범례(Legend) 필수

- **[MUST] 색·선의 의미를 범례로 명시**: 010 §4 팔레트는 색마다 의미가 있고(초록=VPC/VNet, 파랑=Subnet, 파랑점선=Region, 주황점선=Auto Scaling Group, 회색=온프레미스), 엣지는 실선=실제 트래픽/데이터 경로, 점선=논리적 연결(DNS/로그/동기화)입니다. 보는 사람이 이 규약을 추측하게 두지 말고, 다이어그램에 등장한 색·선 종류를 설명하는 범례 박스를 반드시 포함하십시오.
- **[MUST] `legend()` 헬퍼 사용**: `d.legend(id, x, y, entries)`를 호출하십시오. `entries`는 `("box"|"line"|"dash", color, label)` 목록입니다. `box`=컨테이너 테두리색 스와치, `line`=실선 엣지, `dash`=점선 엣지. 실제로 다이어그램에 **등장한 요소만** 범례에 넣고, 실제 사용된 색상만 포함하십시오(005 근거 충실성과 동일 원칙).
- **[MUST] 빈 공간에 배치**: 범례는 캔버스 우상단/우하단 등 컨테이너와 겹치지 않는 여백에 두십시오. 범례 박스는 swimlane이 아니므로 010 §4 팔레트 검사 대상이 아니며 회색 테두리(`#666666`)를 씁니다.
- **[INFO] 자동 검출**: `validate()`가 컨테이너 색 2종 이상 또는 실선+점선 엣지 혼용을 감지했는데 `범례/Legend` 라벨 셀이 없으면 `[WARN] 범례 누락 의심`을 보고합니다. 이 경고가 뜨면 완료 선언 전에 범례를 추가하십시오.

<examples>
<example>
[Good]
```python
d.legend("lg", 1560, 40, [
    ("box", "#147E40", "VPC 경계"),
    ("box", "#007CBC", "Subnet (AWS)"),
    ("box", "#D15100", "Auto Scaling Group"),
    ("line", "#555555", "트래픽/데이터 경로"),
    ("dash", "#555555", "논리적 연결(DNS·로그)"),
])
```
</example>
<example>
[Bad] 범례 없이 초록/파랑/주황 박스만 나열 → 보는 사람이 색의 의미를 알 수 없음
</example>
</examples>

## 2. 제목/범위 블록 필수

- **[MUST] 캔버스 상단에 보이는 제목**: `<diagram name>` 탭 이름만으로는 캔버스를 캡처했을 때 무엇인지 알 수 없습니다. `d.title(id, "대제목", x, y, subtitle="부제")`로 대상 시스템과 범위를 캔버스 좌상단에 표기하십시오.
- **[MUST] 부제에 범위 근거 표기**: 부제에는 클라우드·리전·구성 티어 등 근거 있는 범위를 넣으십시오(예: `AWS · ap-northeast-2 · 3-Tier`). 설명 기반 모드(005 §6)에서 추정한 범위라면 `(가정: ...)`를 병기하십시오.

## 3. 아이콘 라벨 자동 줄바꿈

- **[MUST] `whiteSpace=wrap` 기본 적용**: 툴킷의 `aws_icon()`/`azure_icon()`/`openstack_icon()`/`thirdparty_icon()`/`gitlab_icon()`은 라벨이 아이콘 폭(60px)을 넘을 때 옆 아이콘을 침범하지 않고 자동 줄바꿈되도록 이미 `whiteSpace=wrap`을 포함합니다. 손으로 style을 새로 조립하지 말고 이 헬퍼를 사용하십시오.
- **[MUST] 서브라벨은 여전히 짧게 + `<br>`**: 자동 줄바꿈은 "옆 침범 방지" 안전망일 뿐, 3줄 이상으로 길어지면 아래 행 아이콘과 세로로 부딪힙니다. 서브라벨(`[AZ-A, C 분산 배치]` 등)은 짧게 유지하고 의도한 줄바꿈은 `<br>`로 명시하십시오. `validate()`가 `[WARN] 라벨 폭 초과 의심`을 내면 문장을 줄이십시오.

## 4. 타이포그래피 위계 (글자 크기 통일)

- **[MUST] 고정 위계 사용**: drawio 기본 폰트(12px)만 쓰면 컨테이너 헤더·아이콘 라벨·서브라벨이 모두 같은 크기로 뭉개집니다. 툴킷 상수 `FONT_TITLE=20`(제목) / `FONT_HEADER=13`(컨테이너 헤더) / `FONT_LABEL=12`(아이콘 메인 라벨) / `FONT_SUBLABEL=10`(서브라벨)의 위계를 따르십시오. `container()`/`*_icon()` 헬퍼가 이미 이 값을 주입하므로, 서브라벨의 `<span style="font-size:...">`만 10px로 맞추면 됩니다.
- **[MUST] 임의 폰트 크기 제한**: 위 4단계 외의 크기를 사전 정의된 크기만 엄수하십시오. 강조가 필요하면 크기를 키우는 대신 `fontStyle=1`(굵게)이나 색으로 구분하십시오.

## 5. 검증 및 수락 기준 (Success Criteria)

- **[MUST] 완료 조건 (Done when):**
  1. 다이어그램에 등장한 모든 색·선 종류가 범례에 1:1로 설명되어 있음
  2. 캔버스 좌상단에 제목+범위 블록이 존재함
  3. `render_preview()` PNG를 Read로 열어 범례가 컨테이너와 겹치지 않고, 라벨이 옆 아이콘을 침범하지 않음을 육안 확인
- **[MUST] 검증 도구 매핑:** `python3 ~/dotfiles/contexts/drawio-gen/scripts/layout_toolkit.py {파일경로}`로 `validate()`(겹침/팔레트/라벨폭)를 돌리고, 생성된 `-preview.png`를 육안 확인하십시오.

## 6. 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)

- **[Trigger: Before 완료 선언] 점검 기준 (절차는 015 §5 렌더링 검증 흐름 참조):**
  - 범례 없이 색·선만 나열해 의미 추측을 강요하지 않았는가?
  - 제목/범위 블록이 누락되지 않았는가?
  - 아이콘 라벨이 옆·아래 아이콘을 침범하거나, 근거 없는 임의 폰트 크기를 쓰지 않았는가?
- **[MUST] 중단 조건 (Halt Conditions):** 다이어그램에 색·선 종류가 2가지 이상 등장하는데 범례를 넣을 여백조차 확보하지 못하는 구조라면, 배치를 재검토(종횡비/스택 방향 조정, 015 §3)한 뒤 범례 자리를 만들고 진행하십시오.
