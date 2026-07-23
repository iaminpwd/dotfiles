---
role: Infrastructure Diagram Generator
priority: high
trigger: drawio XML 파일을 생성하거나 수정할 때 적용
references:
  - contexts/dotfiles/references/000-core.md
reviewed: 2026-07-23
---
# DrawIO XML 공통 포맷 규격

## 1. 문서 뼈대 (Document Skeleton)

- **[MUST]** 모든 drawio 파일은 아래 구조를 따르십시오.

<examples>
<example>
[Good]
```xml
<mxfile host="app.diagrams.net" agent="Mozilla/5.0">
  <diagram id="{고유ID}" name="{다이어그램 제목}">
    <mxGraphModel dx="1800" dy="1600" grid="0" gridSize="10"
      guides="1" tooltips="1" connect="1" arrows="1" fold="1"
      page="1" pageScale="1" pageWidth="1800" pageHeight="1600"
      math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- 여기에 노드/엣지 정의 -->
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```
</example>
</examples>

## 2. 노드 타입 3가지

### 2.1 Container (swimlane)
- **[MUST]** 중첩 가능 그룹(Cloud, Region, VPC/VNet, Subnet, ASG 등)에 사용
- **[MUST]** `parent` 속성으로 부모-자식 계층 명시
- **[MUST]** 제목 아래 실선을 없애기 위해 `swimlaneLine=0;` 속성을 반드시 추가하십시오.

```
style="swimlane;whiteSpace=wrap;html=1;fillColor=none;strokeColor={COLOR};startSize={HEADER_HEIGHT};fontStyle=1;fontSize=13;fontColor={COLOR};swimlaneLine=0;"
```

- **[MUST] `{HEADER_HEIGHT}` 기본값**: 계층 레벨별로 아래 값을 고정 기본값으로 사용하고, 특별한 사유 없이 임의로 다른 값을 쓰지 마십시오.

| 계층 레벨 | `startSize` |
|---|---|
| Cloud | `30` |
| Region | `30` |
| VPC/VNet | `40` |
| Subnet | `45` |
| Auto Scaling Group 등 하위 그룹 | `30` |

### 2.2 Icon (리소스 아이콘)
- **[MUST]** AWS: `shape=mxgraph.aws4.*` 기반, Azure: `image=img/lib/azure2/**/*.svg` 기반, OpenStack: 테넌트 리소스 17종은 draw.io 내장 `mxgraph.openstack.*` 스텐실(`openstack_native_icon()`), 컨트롤 플레인 서비스는 네이티브 아이콘이 없으므로 기본 도형(rounded/cylinder/hexagon) + 검정 기본색 + 절제된 강조색(`openstack_icon()` 헬퍼, 상세 규칙은 035 참조)
- **[MUST]** `parent` 속성으로 소속 Subnet/VPC에 귀속
- **[MUST] 기본 크기**: 일반 리소스 아이콘은 `width=60;height=60;`을 기본값으로 사용하십시오. ENI 등 소형 커넥터류 아이콘만 `width=40;height=40;`을 사용하십시오. 근거 없이 임의의 크기를 쓰지 마십시오.

### 2.3 Edge (연결선)
- **[MUST]** `edge="1"` + `source`/`target` 속성으로 연결
- **[MUST]** 공통 스타일:
```
edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;strokeWidth=2;strokeColor=#555555;
```
- 양방향: `startArrow=classic;endArrow=classic;`
- 단방향: `endArrow=classic;`
- 논리적 연결(DNS, 로그 등): `dashed=1;` 추가

## 3. 좌표 체계
- **[MUST]** `<mxGeometry x y width height as="geometry"/>` -- 부모 컨테이너 기준 상대 좌표
- **[MUST]** Container의 `startSize`(헤더 높이)를 고려하여 자식 요소의 y 좌표 설정

## 4. 색상 팔레트 (클라우드 공통)

| 요소 | 색상 | 비고 |
|---|---|---|
| VPC/VNet 테두리 | `#147E40` | 초록 |
| Subnet 테두리 (AWS) | `#007CBC` | 파랑 |
| Subnet 테두리 (Azure) | `#0072C6` | 파랑 |
| Subnet 배경 | `#E6F2F8` | 연한 파랑 |
| Public Subnet 배경 | `#E6F2EB` | 연한 초록 (AWS) |
| Edge 연결선 | `#555555` | 회색 |
| 온프레미스 테두리 | `#555555` | 회색 |
| Internet 클라우드 | `fillColor=#dae8fc` | 연한 파랑 |
| AWS Cloud 테두리 | `#232F3E` | 검정 |
| Azure Cloud 테두리 | `#232F3E` | 검정 |
| Region (AWS) | `#007CBC` dashed | 파랑 점선 |
| Region (Azure) | `#0072C6` dashed | 파랑 점선 |
| OpenStack Cloud/Region/Network | `#232F3E` / `#007CBC` dashed / `#147E40` | AWS 색 재사용 (매핑은 035 §4) |
| OpenStack 서비스 아이콘 테두리 | 기본 `#000000`(검정), 강조 시 `#4A90D9`/`#DA1A32`/`#2E7D32` 중 1개 | OpenStack 공식 색상 표준(035 §0) — 카테고리별 색 구분이 아니라 기본 검정 + 절제된 강조 |
| Auto Scaling Group (AWS) | `#D15100` dashed | 주황 점선 |
| ACA Environment (Azure) | `#0072C6` dashed | 파랑 점선 (Region과 동일) |

## 5. ID 네이밍 컨벤션
- **[MUST]** 의미 기반 소문자 snake_case: `vpc1`, `sub_pub`, `edge_alb_eks`, `vpn_gw`
- **[MUST]** 엣지 ID: `edge_{source}_{target}` 패턴

## 6. 레이아웃 휴리스틱 및 팀 컨벤션
- **[MUST]** swimlane 중첩 계층: Internet/OnPrem(외부) → Cloud → Region → VPC/VNet → Subnet → Resource
- **[MUST]** 외부 요소(Internet, On-Premises)는 좌측 또는 상단에 배치
- **[MUST] 논리적 AZ 병합**: 물리적으로 분리된 가용영역(AZ-A, AZ-C 등)에 배포된 **동일 목적의 서브넷은 절대 개별 박스로 쪼개지 마십시오.** 단일 논리적 Subnet 박스로 통합하고, 박스 이름에 `[AZ-A, C]`를 명시하십시오. (예: `Private subnet [AZ-A, C]`)
- **[MUST] 텍스트 HTML 포맷팅 (CIDR 및 부가 설명)**: VPC나 Subnet의 `value` 속성 내에 CIDR나 부가 설명을 넣을 때는 다음과 같이 HTML 태그를 사용하여 작게 표시하십시오.
  - 예시: `value="VPC 1 (Main)<br><span style=&quot;font-weight:normal;font-size:12px;&quot;>CIDR: 10.0.0.0/16</span>"`
  - 예시: `value="Public subnet [AZ-A, C]<br><span style=&quot;font-weight:normal;font-size:11px;color:#000000;&quot;>대외 서비스 관문 · 10.0.1.0/24</span>"`
- **[MUST] Subnet 헤더에도 CIDR 필수 포함**: Subnet 라벨은 부가 설명 텍스트만 넣지 말고 반드시 해당 서브넷의 CIDR을 함께 표기하십시오(위 두 번째 예시처럼 `설명 · CIDR` 형식 권장). 같은 VPC 안에 같은 AZ 표기(`[AZ-A]` 등)를 공유하는 서브넷이 여러 개 있을 때, CIDR 없이 설명 텍스트만 작은 글씨로 넣으면 육안으로 서로 구분이 안 되어 "같은 서브넷이 중복 등장한 것처럼" 보이는 문제가 실제로 발생했습니다. CIDR은 서브넷을 구분하는 가장 명확하고 근거 있는 값이므로 생략하지 마십시오.
- **[MUST] 리소스 포함 여부 판단 기준 (네트워크 위치 테스트)**: 실제 코드에 존재하는 리소스라도 무조건 개별 아이콘으로 그리지 마십시오. 판단 기준은 "이 리소스가 실제 네트워크 위치(서브넷/ENI/IP)를 갖거나 실행되는 워크로드인가?"입니다. (a) 그렇다면(EKS 클러스터가 서빙하는 애플리케이션, EFS Mount Target처럼 서브넷에 ENI를 갖는 리소스 등) 독립 아이콘으로 그리십시오. (b) 아니라면(ACM 인증서, IAM 정책, KMS 키 정책처럼 다른 리소스에 종속된 설정/보안 메타데이터로 그 자체는 네트워크 위치가 없는 경우) 별도 박스를 만들지 말고 그 리소스가 붙는 대상의 라벨 텍스트로 흡수하십시오. 예: ACM 인증서는 별도 박스 대신 ALB 라벨에 `ALB<br>HTTPS (ACM 인증서)`처럼 붙이십시오.

## 7. 엣지(Edge) 라벨링 규칙

- **[MUST] 라벨 필수 조건**: 서로 다른 서브넷/계층 간 트래픽 흐름이거나 특정 업무적 의미(인증, 동기화, 로그 처리, 라우팅, 터널링 등)를 갖는 연결은 `value` 속성에 반드시 한글 동사구 라벨을 부여하십시오.
  - 예시: `value="AD 계정 동기화"`, `value="트래픽 로그 데이터 처리"`, `value="인증 요청"`, `value="업무망 라우팅"`, `value="IPsec VPN Tunnel"`
- **[MUST] 라벨 생략 허용 조건**: 같은 컨테이너 내 인접 리소스 간 단순 물리적 직결(예: WAF → ALB)이나 Internet → IGW처럼 자명한 연결은 `value=""`로 라벨을 생략해도 됩니다. 모든 엣지에 억지로 라벨을 채우지 마십시오.
- **[MUST] 예시 문자열 그대로 복사 금지**: 위 예시(`AD 계정 동기화` 등)는 "한글 동사구" 형식을 보여주기 위한 참고용일 뿐입니다. 실제 코드/README 근거 없이 예시 문자열을 그대로 가져다 쓰지 말고, 반드시 해당 엣지가 나타내는 실제 데이터 흐름에 맞는 라벨을 새로 작성하십시오.
- **[MUST] 라벨 배경**: 라벨이 있는 edge는 `labelBackgroundColor=#ffffff;`를 스타일에 추가해 배경 도형과 텍스트가 겹치지 않도록 하십시오.
- **[MUST] 핵심 흐름만 엣지로 그리고, 계정 전역 관리형 서비스는 다이어그램에서 제외**: 트래픽/데이터의 주 경로(예: Internet→ALB→EKS, On-Prem→VPN→TGW→VPC)와 하이브리드 연결만 실선/점선 엣지로 그리십시오. CloudTrail/CloudWatch Logs/EventBridge/SQS/KMS처럼 계정 내 다수 리소스에 공통으로 걸리는 관리형 서비스는 개별 리소스마다 엣지를 긋지 마십시오(허브에서 사방으로 뻗는 실타래가 됩니다). 이런 서비스들을 "Management & Governance" 류의 별도 밴드로 묶어 엣지 없이 남겨두는 것도 임시방편일 뿐 최종 해법이 아닙니다 — 엣지를 다 걷어낸 뒤 다이어그램의 나머지 부분과 연결선이 하나도 없는 블록이 남는다면, 그건 애초에 이 네트워크 토폴로지 다이어그램 소속이 아니라는 신호이므로 **블록 자체를 완전히 제거**하십시오. 상세 로그/감사 파이프라인이 중요하면 별도의 "로깅 파이프라인" 다이어그램으로 분리해 그쪽에서 화살표를 포함해 제대로 그리십시오. 계정 레벨 관리형 서비스를 네트워크 토폴로지 다이어그램에서 제외하는 것은 AWS 공식 Architecture Center 다이어그램의 일반적인 관행입니다.

## 8. 다중 AZ 분산 배치 리소스 서브라벨

- **[MUST]** 논리적으로 병합된 서브넷(`[AZ-A, C]`) 안에서, 개별 리소스가 실제로 여러 AZ에 걸쳐 분산 배치되는 관리형/고가용성 리소스는 아이콘 `value`에 10px 크기의 서브라벨을 추가해 분산 배치 사실을 표기하십시오.
  - AWS 예시: API Gateway, Lambda, EKS, ECS
  - Azure 예시: AKS, Azure Functions, App Service, Application Gateway
  - 예시 문자열: `value="API Gateway<br><span style=&quot;font-weight:normal;font-size:10px;&quot;>[AZ-A, C 분산 배치]</span>"`
- **[MUST]** 단일 AZ에서만 동작하는 리소스(예: NAT Instance, 특정 AZ 전용 EC2)는 서브라벨 없이 기본 라벨만 사용하십시오.

## 9. 서드파티/OSS 도구 아이콘 표현

- **[MUST]** AWS/Azure 네이티브 리소스가 아닌 OSS/서드파티 도구는 `040-third-party-icon-library.md`에 확정된 방식(이미지형 또는 shape 예외)을 그대로 적용하십시오. 도구 목록·URL의 SSOT는 040이며 본 절에서 재나열하지 않습니다.

## 10. 레이아웃 계산 원칙 (Layout Calculation)

실제 생성 후 렌더링 검증 과정에서 반복적으로 발견된 좌표 계산 버그(빈 공간 과다, 형제 컨테이너 겹침/계단식 정렬, 헤더-자식 텍스트 겹침)를 재발 방지하기 위한 규칙입니다. 노드 수가 5개를 넘는 다이어그램에서는 좌표를 손으로 하나씩 정하지 말고 아래 원칙에 따라 스크립트로 역산하십시오.

- **[MUST] 공용 툴킷 재사용**: 아래 원칙을 매번 새로 구현하지 말고 `contexts/drawio-gen/scripts/layout_toolkit.py`를 `import`해서 쓰십시오. `grid()`/`hstack()`/`vstack()`/`offset_by_header()`/`subnet_box_size()`가 이미 구현되어 있고, `validate(path)`가 090 검증(ID 중복/끊어진 참조) + 형제 노드 겹침 검사를 한 번에 수행합니다.

- **[MUST] 컨테이너 크기는 콘텐츠로부터 역산**: 컨테이너의 `width`/`height`를 임의의 숫자로 하드코딩하지 마십시오. 내부 아이콘 개수·격자 배치·노트 텍스트 줄 수로부터 필요한 크기를 계산한 뒤 여백(padding)을 더해서 결정하십시오. [Bad] `height=1720` 임의 지정 → 콘텐츠가 830px에서 끝나 890px가 빈 배경으로 남음. [Good] `header + content_height(아이콘 격자에서 계산) + bottom_padding` 공식으로 산출.
- **[MUST] 헤더 높이만큼 자식 y 오프셋 필수**: 자식 요소를 부모 컨테이너에 배치할 때, y좌표는 반드시 부모의 `startSize`(헤더 높이, §2.1 표) 이상에서 시작해야 합니다. 이를 빼먹으면 부모 제목 텍스트와 첫 번째 자식의 헤더 텍스트가 겹칩니다.
- **[MUST] 같은 시각적 행(row)의 형제 컨테이너는 높이를 통일 (단, 콘텐츠 격차가 클 때는 예외)**: 나란히 배치되는 형제 서브넷/컨테이너들은 원칙적으로 그 행에서 가장 콘텐츠가 큰 것의 높이에 맞춰 동일한 높이로 늘리십시오(짧은 쪽은 여백이 남는 것을 허용). 단, 형제 간 콘텐츠 크기(너비 또는 높이) 격차가 1.8배를 넘으면 억지로 같은 행에 묶어 정렬하지 말고, 콘텐츠 크기가 비슷한 것끼리 재그룹하여 별도 행으로 분리하십시오(예: 아이콘 1~2개짜리 작은 서브넷들끼리 한 행, 아이콘 4~5개짜리 큰 서브넷들끼리 한 행). 이 규칙을 지키지 않으면 아이콘 2개짜리 서브넷이 아이콘 5개짜리 서브넷과 같은 크기로 강제 확장되어 내부가 텅 비어 보이는 문제가 실제로 발생했습니다.
  - **[MUST] `row_height()`로 계산만 하고 끝내지 말고 `uniform_row()`로 실제 반영**: `row_height(*heights)`는 통일할 값을 계산해줄 뿐, 그 값을 각 컨테이너의 실제 `height` 인자에 되돌려 적용하는 것은 호출자 책임입니다. his-infra 재생성 작업(2026-07-22)에서 행 간격(vstack) 계산에만 최댓값을 쓰고 정작 각 서브넷 컨테이너의 `height`에는 자기 자신의 원래(더 작은) 값을 그대로 써서, 같은 행인데 바닥선이 어긋나는 회귀가 실제로 발생했습니다. "계산은 했지만 적용을 잊는" 실수를 막기 위해, 값 계산과 반영을 한 번에 강제하는 `uniform_row(*wh_pairs)` — `(w, h)` 목록을 받아 높이가 통일된 `(w, h)` 목록을 반환 — 를 사용하고, 그 반환값을 그대로 각 컨테이너 생성 호출의 `width`/`height` 인자로 넘기십시오. `row_height()`를 직접 쓰는 경우에도 그 반환값을 반드시 모든 형제의 실제 height 인자에 대입했는지 확인하십시오.
- **[MUST] 컨테이너 강제 확장 금지**: 형제 정렬·그리드 폭 통일을 이유로 컨테이너를 자기 콘텐츠보다 현저히 크게 늘리지 마십시오(예: ENI 아이콘 2개짜리 TGW Attachment 서브넷을 옆 대형 서브넷 폭에 맞추려고 전체 폭으로 늘리는 것 — 실제로 발생한 문제입니다). 컨테이너 크기는 항상 자신의 콘텐츠 기준으로 역산하고, 시각적 정렬이 필요하면 컨테이너 자체를 늘리는 대신 좌측 정렬 후 남는 공간을 부모 컨테이너의 여백으로 남기십시오.
- **[MUST] 다이어그램 종횡비 가드레일**: 전체 다이어그램이 세로로 지나치게 길어지지 않도록 관리하십시오(세로:가로 비율 1.4:1 이하 권장). 한 컨테이너 내부의 서브넷이 5개를 초과하면 2열 고정 그리드보다 콘텐츠 크기 티어(위 규칙)에 맞춘 다열 배치를 우선 검토하십시오.
- **[MUST] VPC/VNet 등 최상위 대형 컨테이너는 기본적으로 세로 배치(스택) 우선**: Region 안에 VPC/VNet처럼 그 자체로 서브넷을 여러 개 품는 대형 컨테이너가 2개 이상이면, 기본값으로 위아래로 쌓으십시오(사용자가 스타일 기준으로 지목한 참고 다이어그램 `his-infra-architecture선.drawio`도 VPC1/VPC2를 세로로 쌓아 전체 캔버스가 1800×1600으로 균형 잡힌 비율이었습니다). 가로로 나란히 배치하는 것은, 세로로 쌓았을 때 전체 캔버스가 위 종횡비 가드레일(1.4:1)을 벗어날 정도로 세로가 길어지는 경우에 한해 예외적으로 검토하십시오. 실제로 VPC1/VPC2를 가로 배치했다가 캔버스가 2100×980(가로 2.1:1)까지 옆으로 퍼져 "옆으로 너무 긴" 결과가 나온 사례가 있었습니다.
- **[MUST] 형제 간 간격은 고정 gap 상수로 관리**: 같은 레벨의 형제 요소 사이 x/y 간격은 매번 다른 숫자를 즉흥적으로 쓰지 말고, 레벨별 gap 상수(예: 아이콘 간 30px, 서브넷 간 30px, 행 간 25px)를 정해 일관되게 적용하십시오. 간격이 아이콘 크기보다 좁으면(예: 형제 컨테이너 사이 40px 간격에 60px 아이콘을 끼워 넣는 등) 옆 컨테이너 영역과 겹쳐 보입니다.
- **[MUST] 노드 5개 초과 시 격자/스택 계산 함수 사용**: 아이콘을 한 줄로만 늘어놓지 말고 `cols` 지정 격자 배치 함수로 감싸고, 서브넷/컨테이너 여러 개를 배치할 때도 가로 스택(hstack)·세로 스택(vstack) 헬퍼로 좌표를 계산하십시오. 손으로 좌표를 하나씩 대입하면 간격 불일치·겹침·오프셋 누락이 반복적으로 발생합니다.
- **[MUST] 세로로 쌓인 여러 행의 폭 정렬**: 콘텐츠 크기 격차 때문에 형제를 여러 행(예: 대형 티어 행, 소형 티어 행)으로 나눠 배치할 때, 각 행의 아이템 개수가 다르면 hstack 결과 폭이 행마다 달라져 오른쪽 끝이 계단식으로 어긋나 보입니다. 이 경우 박스 크기를 늘리지 말고 **hstack의 gap을 균등하게 늘려서** 각 행의 전체 폭(`hstack`이 반환하는 두 번째 값)을 통일하십시오. "컨테이너 강제 확장 금지" 규칙은 개별 박스 크기에 적용되는 것이지, 행 사이 간격 조정까지 금지하는 것이 아닙니다.
- **[MUST] 장거리 엣지는 waypoint로 경로 고정**: Region 레벨 아이콘 ↔ Subnet 내부 리소스처럼 2단계 이상의 컨테이너 경계를 가로지르는 엣지는 자동 오소고날 라우팅에 맡기지 마십시오. `layout_toolkit.py`의 `edge()` 헬퍼의 `points` 인자로 최소 1~2개의 중간 경유점(부모 컨테이너 좌표계 기준)을 지정해, 선이 다른 컨테이너를 뚫고 지나가며 지저분해 보이는 것을 방지하십시오.
- **[MUST] 여러 엣지가 한 타겟에 모이면 각각 실제 중점을 waypoint로 명시**: `render_preview()`는 waypoint 없는 2점 엣지의 라벨을 `pts[len(pts)//2]`(경유점이 없으면 결국 타겟 중심)에 그린다. VM/허브처럼 여러 엣지가 같은 타겟으로 모이는 구조에서는 모든 라벨이 타겟 중심 한 점에 겹쳐 보인다(2026-07-23, openstack-basic Conceptual Architecture 작업에서 실측 확인). 소스·타겟의 절대 좌표로 `((sx+tx)/2, (sy+ty)/2)`를 직접 계산해 `points=[(mx, my)]`로 넘기면, 엣지마다 다른 위치에 라벨이 표시되어 겹침이 사라진다. 실제 drawio가 기본적으로 경로 중점에 라벨을 놓는지는 별개 문제이므로, 이 waypoint 지정은 미리보기 정확성과 실제 파일의 견고함을 동시에 확보하는 차원에서 항상 적용하라.
- **[MUST] 생성 직후 렌더링 검증**: 090 문서의 ID/참조 무결성 검증만으로는 겹침·정렬·엣지 라우팅 문제를 못 잡습니다. XML 저장 직후 `layout_toolkit.py`의 `validate(path)`를 실행해 형제 겹침, **행 높이 불일치([WARN] 행 높이 불일치)**, **라벨 폭 초과([WARN] 라벨 폭 초과 의심)** 까지 확인하십시오. 그다음 임시 렌더러를 매번 새로 짜지 말고 `layout_toolkit.py`의 `render_preview(path, out_png)`를 호출해 **엣지(연결선)까지 포함된** PNG를 Read 도구로 실제로 열어 박스 정렬뿐 아니라 연결선이 다른 서브넷 내부를 뚫고 지나가지는 않는지 육안으로 확인한 뒤에만 완료를 선언하십시오. 서드파티 아이콘을 썼다면 네트워크가 가능한 경우 `check_icon_urls(path)`로 이미지 URL 생존 여부도 확인하십시오(죽은 링크는 [WARN], 네트워크 불가는 [INFO]로만 표시되며 완료 조건을 막지 않음). 말로 "정렬했습니다"라고 보고하기 전에 반드시 눈으로 확인하십시오. `validate()`가 행 높이 불일치를 경고하면 완료 선언 전에 반드시 `uniform_row()`를 적용해 재생성하고, 라벨 폭 초과를 경고하면 서브라벨 문장을 줄이거나 `<br>`로 나누십시오.
