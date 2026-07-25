---
role: Infrastructure Diagram Generator
priority: high
trigger: Azure 관련 drawio XML 파일을 생성하거나 수정할 때 적용
references:
  - contexts/drawio-gen/references/010-drawio-xml-standard.md
  - contexts/drawio-gen/references/040-third-party-icon-library.md
reviewed: 2026-07-24
---
# Azure 아이콘 스타일 라이브러리 매핑

본 모듈은 Azure 아키텍처 다이어그램 생성 시 사용되는 아이콘들의 Image 속성 및 색상 매핑 가이드입니다.

> [!TIP]
> Azure 아이콘은 draw.io 내장 SVG 라이브러리(`img/lib/azure2/`)를 참조합니다. 별도 이미지 파일(base64 등) 삽입 없이 draw.io에서 즉시 렌더링됩니다.

## 0. 공식 아이콘 사용 가이드라인 (SSOT — 원문 그대로 적용)

출처: Microsoft 공식 Azure Architecture Center "Azure Icons" 페이지
https://learn.microsoft.com/en-us/azure/architecture/icons/
(조회일: 2026-07-24, 문서 `ms.date`: 2026-07-09)

> **[MUST] 이 절은 여러 사례를 보고 유추한 관행이 아니라 Microsoft가 실제로 발행한
> 규정입니다. 임의 해석 없이 원문 그대로 적용하십시오.**

**일반 가이드라인(General guidelines) — 원문 그대로 인용**
> "Do's — Use the icon to illustrate how products can work together. In
> diagrams, we recommend including the product name somewhere close to the
> icon. Use the icons as they would appear within Azure. / Don'ts — Don't
> crop, flip, or rotate icons. Don't distort or change icon shape in any way.
> Don't use Microsoft product icons to represent your product or service."

- **[MUST]** 아이콘을 크롭·반전·회전하거나 형태를 왜곡하지 마십시오. §1 템플릿의
  `image={IMAGE_PATH}` SVG를 원본 그대로 참조하고, 별도 가공(리사이즈 시 종횡비
  변경 등)을 하지 마십시오.
- **[MUST]** 아이콘 근처에 제품명을 병기하는 것을 권장합니다 — §1 템플릿의
  `verticalLabelPosition=bottom` 라벨 배치가 이 권고와 일치합니다.
- **[MUST]** Microsoft 제품 아이콘을 사용자 자신의 제품/서비스를 나타내는 용도로
  대체 사용하지 마십시오. Azure 네이티브 서비스가 아닌 대상에는 §3(서드파티
  아이콘, 040 SSOT)을 적용하고 Azure 아이콘을 오용하지 마십시오.

**라이선스(Icon terms) — 원문 그대로 인용**
> "Microsoft permits the use of these icons in architectural diagrams,
> training materials, or documentation. You can copy, distribute, and display
> the icons only for the permitted use unless granted explicit permission by
> Microsoft."

- **[MUST]** 아키텍처 다이어그램·교육 자료·문서 목적 범위 내에서만 아이콘을
  사용하십시오. 로고/상표 대체 등 이 범위를 벗어난 용도로 사용하지 마십시오.

## 1. Azure 공통 Style 템플릿

- **[MUST]** Azure 리소스 아이콘에는 다음 템플릿을 기반으로 `{IMAGE_PATH}`를 치환하여 사용하십시오.

```xml
image;aspect=fixed;html=1;points=[];align=center;fontSize=10;
image={IMAGE_PATH};verticalLabelPosition=bottom;verticalAlign=top;
```

## 2. 아이콘 매핑 테이블

| Azure 리소스 | drawio image path (`{IMAGE_PATH}`) | 카테고리 |
|---|---|---|
| VPN Gateway | `img/lib/azure2/networking/Virtual_Network_Gateways.svg` | Networking |
| NAT Gateway | `img/lib/azure2/networking/NAT.svg` | Networking |
| DNS Zones / Resolver | `img/lib/azure2/networking/DNS_Zones.svg` | Networking |
| Private Link / Endpoint | `img/lib/azure2/networking/Private_Link.svg` | Networking |
| Virtual Network (VNet) | `img/lib/azure2/networking/Virtual_Networks.svg` | Networking |
| Load Balancer | `img/lib/azure2/networking/Load_Balancers.svg` | Networking |
| Application Gateway | `img/lib/azure2/networking/Application_Gateways.svg` | Networking |
| Front Door | `img/lib/azure2/networking/Front_Doors.svg` | Networking |
| Azure Firewall | `img/lib/azure2/networking/Firewalls.svg` | Networking |
| Container Registry (ACR) | `img/lib/azure2/containers/Container_Registries.svg` | Containers |
| App Services (ACA/Web App) | `img/lib/azure2/containers/App_Services.svg` | Containers |
| Kubernetes Services (AKS) | `img/lib/azure2/containers/Kubernetes_Services.svg` | Containers |
| Virtual Machines (VM) | `img/lib/azure2/compute/Virtual_Machines.svg` | Compute |
| VM Scale Sets (VMSS) | `img/lib/azure2/compute/VM_Scale_Sets.svg` | Compute |
| Azure Functions | `img/lib/azure2/compute/Function_Apps.svg` | Compute |
| Storage Accounts | `img/lib/azure2/storage/Storage_Accounts.svg` | Storage |
| SQL Databases | `img/lib/azure2/databases/SQL_Databases.svg` | Database |
| Cosmos DB | `img/lib/azure2/databases/Azure_Cosmos_DB.svg` | Database |
| Azure Cache for Redis | `img/lib/azure2/databases/Azure_Cache_for_Redis.svg` | Database |
| Service Bus | `img/lib/azure2/integration/Service_Bus.svg` | Integration |
| Event Grid | `img/lib/azure2/integration/Event_Grid_Domains.svg` | Integration |
| Key Vault | `img/lib/azure2/security/Key_Vaults.svg` | Security |
| Microsoft Entra ID (Azure AD) | `img/lib/azure2/identity/Azure_Active_Directory.svg` | Identity |
| Log Analytics Workspace | `img/lib/azure2/management_governance/Log_Analytics_Workspaces.svg` | Monitoring |
| Application Insights | `img/lib/azure2/management_governance/Application_Insights.svg` | Monitoring |
| Azure Monitor | `img/lib/azure2/management_governance/Monitor.svg` | Monitoring |

- **[MUST] 예외 — Traditional Server (온프레미스 서버)**: 이 리소스는 본 절 §1의 `image={IMAGE_PATH}` 템플릿 대상이 아닙니다. 위 테이블에 값을 대입하지 말고, 020(AWS) §1 템플릿과 동일한 shape 기반 스타일을 그대로 사용하십시오: `outlineConnect=0;fontColor=#232F3E;gradientColor=none;fillColor=#5294FF;strokeColor=none;dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;aspect=fixed;shape=mxgraph.aws4.traditional_server;`

## 3. 3rd Party Custom Icon (팀 컨벤션)

- **[MUST]** Azure 기본 서비스가 아닌 오픈소스/서드파티 도구(Jenkins/ArgoCD/Prometheus/Grafana/GitLab 등)의 아이콘 표현 방식은 클라우드 공통 SSOT인 `040-third-party-icon-library.md`를 그대로 적용하십시오. 본 문서에서 재나열하지 않습니다.

## 4. 컨테이너 색상 (Azure)

- **[MUST]** Azure Cloud/Region/VNet/Subnet/ACA Environment 컨테이너 색상은 010 §4 "색상 팔레트 (클라우드 공통)" 표를 그대로 적용하십시오. SSOT는 010이며 본 절에서 재나열하지 않습니다. (Azure Cloud도 010과 동일하게 검정 `#232F3E`이며 Azure 브랜드 파랑이 아님에 유의하십시오.)
