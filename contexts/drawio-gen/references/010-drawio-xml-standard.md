---
role: Infrastructure Diagram Generator
priority: high
trigger: drawio XML 파일을 생성하거나 수정할 때 적용
references:
  - contexts/dotfiles/references/000-core.md
reviewed: 2026-07-27
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
| **OpenStack 강조 3색** | `#4A90D9` / `#DA1A32` / `#2E7D32` | **OpenStack 다이어그램 전용 — 아래 우선순위 규칙 참조** |

- **[MUST] OpenStack 다이어그램에서는 035 §0이 이 표보다 우선**: 위 표는 AWS/Azure에서 출발한 클라우드 공통 팔레트라 회색(`#555555`/`#888888`)·주황(`#D15100`) 등 무채색·비원색이 섞여 있습니다. 그러나 OpenStack 공식 다이어그램 표준은 *"Colored objects may only use bright primary colors, such as light blue, red, or green"*으로 **밝은 원색 3종만** 허용합니다. 따라서 OpenStack 다이어그램에서 컨테이너를 색으로 구분해야 할 때는 이 표의 회색 계열을 가져다 쓰지 말고 `#4A90D9`/`#DA1A32`/`#2E7D32` 중에서 고르십시오. openstack-basic 논리 아키텍처에서 "비-OpenStack 공유 인프라" 컨테이너에 `#888888`을 썼다가 표준 위반으로 적발된 실사례가 있습니다(2026-07-25). 색상 hex는 권장값이며, 공식 규정이 구속하는 것은 **색 계열**(light blue / red / green)입니다.
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
- **[MUST] "대표 엣지 1개 + 공통 라벨" 패턴을 쓸 때는 고립 그룹이 생기는지 먼저 확인**: DB·메시지 브로커처럼 다수가 공유하는 허브는 소비자마다 선을 긋는 대신 대표 1개만 긋고 라벨에 `(A·B·C 공통)`을 명시하는 것이 위 규칙의 실행 방법입니다. 다만 **어떤 소비자에게 그 선이 유일한 외부 연결이면 지우는 순간 그 그룹 전체가 다이어그램에서 떠버립니다.** 실사례(2026-07-25, openstack-basic): RPC 선 3개를 1개로 줄이려다 `cinder-api`의 유일한 연결이 사라져 Cinder 그룹 3개 박스가 고립되는 것을 발견하고 2개까지만 줄였다. 엣지를 제거하기 전에 각 컨테이너의 **외부 연결 차수(자식 엣지를 부모로 전파해 집계)** 를 세어 0이 되는 그룹이 없는지 확인하십시오.
- **[MUST] 엣지 라벨을 달기 전에 "라벨 폭 vs 배치 간격"을 먼저 계산**: 인접 박스 사이 gap이 좁은 구간(예: 격자 배치의 35px 간격)에 라벨을 넣으면 `labelBackgroundColor` 흰 배경이 양옆 박스 테두리를 덮어 오히려 그림을 훼손합니다. 한글 라벨 추정 폭은 `글자수 × fontSize × 0.95` 로 어림하고, 이 값이 gap보다 크면 **라벨을 달지 말고** 그 정보를 노트나 슬라이드 설명 텍스트로 옮기십시오. 실사례: OVN 체인(`neutron-server → NB DB → ovn-northd → SB DB → ovn-controller`)은 gap 35px인데 후보 라벨이 최소 52px, 원안은 136px이라 라벨을 포기하고 무라벨로 유지했다 — 박스 이름 자체가 이미 순서와 의미를 전달하므로 정보 손실도 없었다.
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

좌표·크기 역산, 형제 정렬, 엣지 waypoint, 생성 직후 배치 검증 규칙은 `015-layout-calculation-standard.md`로 분리되었습니다. 노드 5개를 넘는 다이어그램을 생성할 때는 해당 모듈을 참조하십시오.
