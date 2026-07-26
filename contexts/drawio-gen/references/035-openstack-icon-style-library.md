---
role: Infrastructure Diagram Generator
priority: high
trigger: OpenStack 관련 drawio XML 파일을 생성하거나 수정할 때 적용
references:
  - contexts/drawio-gen/references/010-drawio-xml-standard.md
  - contexts/drawio-gen/references/040-third-party-icon-library.md
reviewed: 2026-07-23
---
# OpenStack 아이콘 스타일 라이브러리 매핑

본 모듈은 OpenStack 아키텍처 다이어그램 생성 시 사용되는 아이콘의 Style 속성과,
OpenStack이 실제로 발행한 다이어그램 작성 표준(색상/선/도형 규칙)을 정의합니다.

## 0. 공식 색상/선/도형 표준 (SSOT — 반드시 원문 그대로 적용)

출처: OpenStack 공식 Documentation Contributor Guide
https://docs.openstack.org/doc-contrib-guide/diagram-guidelines/general-guidelines.html
(조회일: 2026-07-23)

> **[MUST] 이 절은 여러 사례를 보고 유추한 관행이 아니라 OpenStack이 실제로 발행한
> 규정입니다. 임의 해석 없이 원문 그대로 적용하십시오.**

**객체 색상 (Object color) — 원문 그대로 인용**
> "Any objects inside a diagram should be black, unless the object needs to be
> emphasized within a diagram in order to fully understand its function. Colored
> objects may only use bright primary colors, such as light blue, red, or green.
> You can make multiple objects the same color, provided the objects serve
> similar functions or purposes."

- **[MUST] 기본값은 검정**: 강조가 필요 없는 객체는 검정 테두리(+흰 배경)로 그리십시오.
- **[MUST] 강조색은 밝은 원색 3종 한정**: `light blue`(#4A90D9) / `red`(#DA1A32) /
  `green`(#2E7D32)만 사용하십시오. 파스텔/보라/주황 등 원색이 아닌 색이나, 카테고리마다
  다른 색을 5~6개씩 쓰는 것은 이 표준에 맞지 않습니다.
- **[MUST] 동일 기능 = 동일 색 재사용**: 같은 기능/목적의 객체군(예: "API 진입점"
  역할을 하는 Keystone/Nova-api/Neutron-server 등)은 같은 강조색을 재사용해 그룹으로
  묶으십시오. 서비스마다 새 색을 배정하지 마십시오.

**객체 형태 (Objects) — 원문 그대로 인용**
> "An object must be a closed geometric shape or icon. Objects must have a
> hollow middle, where text can be added. All objects must be labeled according
> to their function."

- **[MUST]** 닫힌 기하 도형 또는 아이콘만 사용하고, 라벨 텍스트가 들어갈 여백을
  반드시 확보하십시오. (아이콘 자체는 표준상 허용되나, 1절의 이유로 OpenStack은
  프로젝트 전용 로고 아이콘이 실질적으로 존재하지 않는다.)

**선 (Lines) — 원문 그대로 인용**
> "Set line width to at least 2px or above. Avoid crossing an object with a
> line." / "Keep lines straight unless a line needs to change direction. If a
> line changes direction to reach an object, the corner in which the change of
> direction occurs must be rounded." / Solid lines: "direct relationship
> between objects." / Dashed lines: "group objects connected through an online
> network." / Dotted lines: "how data entered by a human user travels."

| 선 종류 | 공식 의미 | 최소 굵기 | 꺾임 |
|---|---|---|---|
| 실선 | 객체 간 직접적 관계 | 2px | 둥근 모서리 |
| 점선(dashed) | 온라인 네트워크로 연결된 객체 그룹 | 2px | 둥근 모서리 |
| 점-선(dotted) | 사람이 입력한 데이터의 이동 경로 (예: 사용자→API 요청) | 2px | 둥근 모서리 |

- **[MUST]** `layout_toolkit.py`의 `edge()`는 `dashed=True`/`dotted=True` 불리언
  인자로 위 3종(둘 다 `False`=실선)을 지원한다. 사용자 입력이 흐르는 엣지(로그인
  폼 제출, Horizon/CLI에서 발생한 최초 요청 등)에는 반드시 `dotted=True`를 쓰고,
  지금까지처럼 "논리적 연결"이라는 이유로 전부 `dashed=True`로 뭉뚱그리지 마십시오.
  두 인자를 동시에 `True`로 주지 않는다(`dotted`가 우선 적용됨).

## 1. draw.io 내장 OpenStack 스텐실 (실재함 — 과거 버전 문서 정정)

> [!IMPORTANT]
> 과거 버전 문서는 "draw.io에 OpenStack 네이티브 스텐실이 없다"고 기술했으나
> **이는 사실이 아니었습니다.** draw.io는 `mxgraph.openstack.*` 내장 스텐실
> 라이브러리를 제공합니다(에디터의 More Shapes → Networking → OpenStack). 다만
> 이 라이브러리는 **테넌트 리소스 17종**만 제공하며, Keystone/Glance/Horizon/
> Neutron-Server 데몬/OVN DB 같은 **컨트롤 플레인 서비스 아이콘은 draw.io에도,
> OpenStack 공식 브랜드 자료에도 존재하지 않습니다.**
> 출처: jgraph/drawio 저장소 `src/main/webapp/js/diagramly/sidebar/Sidebar-OpenStack.js`
> (조회일: 2026-07-23)

- **[MUST] 실제 리소스와 정확히 일치할 때만 사용**. 스타일 문자열:
  ```
  aspect=fixed;sketch=0;pointerEvents=1;shadow=0;dashed=0;html=1;strokeColor=none;
  labelPosition=center;verticalLabelPosition=bottom;outlineConnect=0;verticalAlign=top;
  align=center;shape=mxgraph.openstack.{name};fillColor=#{COLOR};
  ```
  `{name}` (17종 고정, 임의 이름 창작 금지): `cinder_volume`, `cinder_volumeattachment`,
  `designate_recordset`, `designate_zone`, `heat_autoscalinggroup`, `heat_resourcegroup`,
  `heat_scalingpolicy`, `neutron_floatingip`, `neutron_floatingipassociation`,
  `neutron_net`, `neutron_port`, `neutron_router`, `neutron_routerinterface`,
  `neutron_securitygroup`, `neutron_subnet`, `nova_keypair`, `nova_server`,
  `swift_container`.
  `{COLOR}`: draw.io가 이 스텐실 전용으로 제공하는 4색 중 하나만 —
  `3F51B5`(Blue) / `808080`(Grey) / `008000`(Green) / `C82128`(Red). 이 4색
  팔레트는 draw.io 에디터 UI 자체가 제공하는 스텐실 전용 색상이며, 0절의
  "밝은 원색 3종" 규칙과는 별개 체계다. 네이티브 스텐실을 쓸 때는 이 4색에서,
  2절의 기능형 블록을 쓸 때는 0절 규칙을 따르라.
- **[MUST] 이름 유사성만으로 대체 금지**: 매핑 테이블에 없는 서비스는 억지로
  끼워 맞추지 말고 2절의 기능형 블록으로 대체하거나 사용자에게 확인하십시오.

## 2. 컨트롤 플레인 서비스 — 기능형 블록 (네이티브 스텐실이 없는 경우)

> [!IMPORTANT]
> Keystone/Glance/Horizon/Neutron-Server/Cinder-API/OVN DB 등 컨트롤 플레인
> 서비스는 draw.io에도 OpenStack 공식 자료에도 아이콘이 없다. 기본 도형으로
> 표현하되 **0절의 공식 색상 표준을 그대로 적용**하라 — 기본은 검정 테두리, 강조가
> 꼭 필요한 대상에만 밝은 원색(하늘색/빨강/초록) 중 하나. "OpenStack 레드 테두리
> 고정 + 카테고리별 파스텔 5~6색"을 기본값으로 쓰던 과거 관행은 폐기한다 — 이는
> 팀이 만든 스타일일 뿐 공식 표준이 아니었고, 실제 표준은 색을 아껴 쓰는 쪽이다.

- **[MUST] 기본 스타일**: `openstack_icon()` 헬퍼 사용, `emphasis=None`(기본)이면
  검정 테두리 + 흰 배경 + 검정 텍스트. 기본 크기는 `w=90,h=70`(다른 아이콘류의
  60x60보다 큼).
  ```xml
  {SHAPE}whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#000000;strokeWidth=2;
  fontColor=#000000;verticalLabelPosition=bottom;verticalAlign=top;align=center;
  fontSize=12;aspect=fixed;
  ```
- **[MUST] 라벨은 도형 "아래"에 배치 — `aws_icon()`/`azure_icon()`/
  `openstack_native_icon()`과 동일한 관례**: `verticalLabelPosition=bottom`을
  쓴다(사용자가 아이콘류 공통 스타일을 선호함을 확인, 2026-07-23). `openstack_icon()`의
  rounded/cylinder/hexagon은 실제 픽토그램이 없는 빈 도형이라 라벨이 상대적으로
  허전해 보일 수 있으나, 대신 **기본 크기를 60x60보다 크게(90x70)** 잡아 도형
  자체의 존재감을 키우고 라벨과의 시각적 균형을 맞춘다.
- **[MUST] 크기를 키우면 행/열 간격도 함께 늘릴 것**: `openstack_icon()`을
  `grid()`/`hstack()`/`vstack()`과 함께 쓸 때, 기본 크기(90x70)와 다국어/여러 줄
  라벨 분량에 맞춰 `gy`(행 간격)를 최소 90 이상으로 넉넉히 지정하라. 도형 크기만
  키우고 간격 상수를 그대로 두면 라벨이 다음 행 요소와 다시 겹치는 회귀가
  발생한다(2026-07-23, openstack-basic Logical Architecture 작업에서 실측 확인).
- **[MUST] `openstack_icon()`을 swimlane 컨테이너 안에 넣을 때는 컨테이너 자체
  높이에도 라벨 공간을 반영할 것**: 라벨이 도형 "아래"에 그려지므로, `grid()`가
  반환한 콘텐츠 높이(`ch`)는 도형 높이만 반영하고 그 아래 라벨 줄 공간은 포함하지
  않는다. 이 콘텐츠를 감싸는 swimlane을 `subnet_box_size(cw, ch, header=...)`로
  만들 때 `extra_below`(최소 40~45)를 반드시 함께 지정하라. 빠뜨리면 라벨 텍스트가
  swimlane의 파란 경계선 밖으로 삐져나온다(2026-07-23, openstack-basic Logical
  Architecture 작업에서 실측 확인 — Nova/Neutron/Cinder/Glance 그룹 박스 전부 이
  문제를 겪었다). `grid()`가 이미 gy로 "행 사이" 간격은 처리하므로, `extra_below`는
  그 그룹의 "마지막 행 아래"에 한정된 별도 여백이다 — 서로 다른 문제이니 둘 다
  챙길 것.
- **[MUST] 강조는 3색 중 하나만, 테두리로만**: 정말 강조가 필요할 때만
  `emphasis="blue"|"red"|"green"`을 지정한다. 배경까지 원색으로 채우지 말고
  테두리(strokeWidth=3)만 강조색으로 바꿔 텍스트 라벨 가독성을 유지한다.
- **[MUST] 동일 기능 = 동일 강조색 재사용**: 예) "API 진입점"이라는 동일 역할의
  여러 서비스(Keystone/Nova-api/Neutron-server/Cinder-api/Glance-api)에는 전부
  같은 강조색(예: red)을 재사용하고, 서비스마다 새 색을 만들지 마십시오.
- **[MUST] `{SHAPE}` 도형 토큰 — `rounded` / `cylinder` 2종만 사용**:
  `rounded`(기본형 — API·워커·브로커 등 모든 프로세스) / `cylinder`(DB, 이미지·볼륨
  저장소 등 데이터 저장소). 도형 구분은 색상 규칙과 무관한 별개 축이므로 0절의 색상
  제한을 받지 않는다.
  - **[MUST] `hexagon` 사용 금지 (2026-07-25 폐기)**: 이전 판본은 `hexagon`을
    "네트워크 관련 데몬·큐"에 배정했으나 폐기한다. 근거는 세 가지다.
    (1) **공식 표준은 도형에 의미를 부여하지 않는다** — 원문은 *"An object must be a
    closed geometric shape or icon ... All objects must be labeled **according to their
    function**"* 로, 의미 전달 책임을 **라벨**에 두고 도형 종류에는 아무 제약도 규정도
    없다. 색·선에는 세밀한 규칙을 두면서 도형만 자유롭게 남긴 것은 의도적이다.
    (2) **육각형에는 보편적 의미가 없다** — 원통=데이터 저장소는 플로차트 시대부터
    내려온 IT 전반의 관례라 범례 없이 통하지만, 육각형=큐는 널리 쓰이는 관례가 아니라
    반드시 범례가 필요해진다. 실무에서 메시지 브로커는 사각형+라벨 또는 로고 아이콘으로
    그리는 것이 일반적이다.
    (3) **규칙이 절반만 지켜져 오히려 오독을 만든다** — openstack-basic 논리
    아키텍처에서 큐(RabbitMQ)만 육각형이 되고 정작 네트워크 데몬(ovn-northd,
    ovn-controller, neutron-server)은 전부 사각형이라, 사실상 "RabbitMQ 전용 도형"이
    되어 "왜 이것만 다르지?"라는 질문을 유발했다.
  - **[MUST] 도형 종류가 3종을 넘으면 범례에 도형 항목을 넣을 것**: 사각형은 개수가
    가장 많아 "기본형"으로 읽히므로 설명이 불필요하고, 원통은 보편 관례라 설명 없이
    통한다. 그 외 도형을 추가하는 순간 범례 설명이 필수가 되므로, **범례를 늘릴
    각오가 없으면 도형을 늘리지 마십시오.**

## 3. 3rd Party Custom Icon (팀 컨벤션)

- **[MUST]** OpenStack 네이티브 서비스가 아닌 오픈소스/서드파티 도구(Jenkins/ArgoCD/
  Prometheus/Grafana/GitLab 등)의 아이콘 표현 방식은 클라우드 공통 SSOT인
  `040-third-party-icon-library.md`를 그대로 적용하십시오. 본 문서에서 재나열하지
  않습니다.

## 4. 컨테이너 색상 및 계층 매핑 (OpenStack)

- **[MUST]** OpenStack 계층은 `Cloud > Region > Neutron Network(VPC/VNet 자리) >
  Subnet > Resource`로 매핑하고, 컨테이너(swimlane) 색은 010 §4 "색상 팔레트
  (클라우드 공통)" 표의 **기존 승인 색을 그대로 재사용**하십시오(SSOT는 010, 본
  절에서 재나열 금지).
  - OpenStack Cloud 테두리: `#232F3E`(검정, AWS/Azure와 동일)
  - Region (OpenStack): `#007CBC` dashed(파랑 점선)
  - Neutron Network 테두리: `#147E40`(초록, VPC/VNet과 동일)
  - Subnet 테두리: `#007CBC`(파랑)
- **[MUST] 컨테이너도 0절 색상 제한을 따를 것 (예외 조항 폐기)**: 이전 판본은
  "컨테이너는 객체가 아니라 구조적 그룹핑 경계이므로 0절 제한 대상이 아니다"라는
  예외를 두었으나, **공식 원문에는 그런 예외의 근거가 없습니다.** 원문은 객체를
  *"a closed geometric shape ... must have a hollow middle, where text can be added"*로
  정의하는데 swimlane 컨테이너는 이 정의에 정확히 부합합니다. 따라서 컨테이너 테두리도
  **검정(기본) 또는 밝은 원색 3종(`#4A90D9`/`#DA1A32`/`#2E7D32`)** 안에서 고르고,
  회색(`#888888`/`#555555`) 같은 무채색은 쓰지 마십시오.
  - 실사례(2026-07-25, openstack-basic): "비-OpenStack 공유 인프라" 컨테이너에
    `#888888`을 썼다가 색상 감사에서 적발 → `#2E7D32`(green)로 교체. 010 §4 팔레트
    표에 OpenStack 강조 3색이 없어 `validate()`가 오히려 정상 색을 위반으로 잡는
    2차 충돌까지 발생했다. 010 §4와 본 절이 어긋나면 **본 절(공식 원문)이 우선**이다.
  - drawio 기본 도형 색(예: 클라우드 스텐실의 `fillColor=#dae8fc`/`strokeColor=#6c8ebf`)을
    그대로 두지 마십시오. 이것도 원색이 아니므로 흰 채움 + 검정 테두리로 교체합니다.
- **[MUST] AZ 서브라벨 공통 적용**: Nova Availability Zone에 분산된 동일 목적
  서브넷/리소스는 010 §7·§8의 `[AZ-A, C]` 논리 병합 및 서브라벨 규칙을 그대로
  적용하십시오.

## 5. 아이콘-리소스 정확성 가드레일 (Icon Fidelity)

- **[MUST] 네이티브 스텐실 창작 금지**: `mxgraph.openstack.*`는 실재하는 17종
  (1절)만 유효합니다. 그 외 이름이나 OpenStack 프로젝트 로고 URL을 지어내지
  마십시오.
- **[MUST] 이름 유사성만으로 대체 금지**: 실제 리소스 타입과 정확히 일치하는
  서비스에만 해당 도형을 사용하고, 매핑 테이블에 없는 서비스는 억지로 끼워
  맞추지 말고 `note()`(rect+텍스트)로 대체하거나 사용자에게 확인하십시오.

## 6. 아키텍처 팩트 가드레일 (OpenStack 도메인 — 반복 발생한 오류)

openstack-basic 작업(2026-07-25)에서 실제로 그렸다가 공식 문서 대조로 정정한
사실들입니다. 개념/논리 아키텍처를 그릴 때마다 아래를 먼저 확인하십시오.
출처는 모두 `docs.openstack.org/install-guide` 및 `docs.openstack.org/nova/latest`
(조회일 2026-07-25).

- **[MUST] AMQP 브로커는 "한 서비스 내부의 프로세스 간" 통신용**
  > "For communication between the processes of **one service**, an AMQP message broker is used."
  > "Individual services interact with each other **through public APIs**."

  Nova·Neutron·Cinder 는 같은 RabbitMQ 인스턴스를 공유할 뿐 서로 메시지를 주고받지
  않습니다. 따라서 여러 서비스의 RPC 선을 하나의 버스처럼 겹쳐 그리면 **공식 정의가
  명시적으로 부정하는 구조**가 됩니다. 실제로 3개 선을 트렁크로 합쳤다가 이 이유로
  되돌린 사례가 있습니다. 라벨은 `RPC 메시징(nova-api · scheduler · conductor · compute 간)`
  처럼 **그 서비스 내부 프로세스만** 나열하십시오.

- **[MUST] Glance 는 VM 이 아니라 Nova 에 이미지를 제공**
  이미지를 받는 시점에는 VM 이 아직 존재하지 않습니다. nova-compute 가 Glance API 에서
  이미지를 내려받아 인스턴스 루트 디스크를 만듭니다. 개념 아키텍처에서 `Glance → VM`
  화살표를 그리지 말고 `Nova ↔ Glance` 왕복(조회/제공)으로 그리십시오. 공식 개념도도
  `Glance --provides images--> Nova` 형태입니다.

- **[MUST] nova-compute 는 DB 에 직접 접근하지 않음**
  > "Services running on the compute node **proxy database requests over RPC to a central
  > manager called the conductor**." / "The API servers process REST requests, which
  > typically involve database reads/writes."

  DB 연결선을 그린다면 nova-api 또는 nova-conductor 에서 뽑으십시오. nova-compute 에서
  DB 로 선을 긋는 것은 오류입니다.

- **[MUST] 개념(Conceptual) 계층은 "서비스 간 역할 관계"**
  공식 Conceptual architecture 는 서비스끼리의 관계도이며 프로세스·데몬을 그리지
  않습니다. VM 노드를 중심에 두는 변형은 읽기 쉬워 실무에서 흔히 쓰이지만, 공식 구성과
  다르다는 점을 주석에 밝히십시오. Placement 처럼 배포는 되지만 개념 계층에서 생략하는
  서비스가 있으면 **생략 사유를 주석에 명시**해야 "누락"으로 읽히지 않습니다.
