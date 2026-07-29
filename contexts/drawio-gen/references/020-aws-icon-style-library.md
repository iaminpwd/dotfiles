---
role: Infrastructure Diagram Generator
priority: high
trigger: AWS 관련 drawio XML 파일을 생성하거나 수정할 때 적용
references:
  - contexts/drawio-gen/references/010-drawio-xml-standard.md
  - contexts/drawio-gen/references/040-third-party-icon-library.md
---
# AWS 아이콘 스타일 라이브러리 매핑

본 모듈은 AWS 아키텍처 다이어그램 생성 시 사용되는 아이콘들의 Shape 속성 및 색상 매핑 가이드임.

## 0. 공식 아이콘 사용 가이드라인 (SSOT — 원문 그대로 적용)

출처: AWS 공식 "AWS Architecture Icons" 배포 자료(PowerPoint 자산 패키지, Release 23-2026.04.28) Guidelines
섹션(슬라이드 14~18, 25). 자산 패키지 다운로드 페이지:
https://aws.amazon.com/architecture/icons/
(조회일: 2026-07-24, 원본 zip: `Microsoft-PPTx-toolkits_04302026.zip` → `AWS-Architecture-Icons-Deck_For-Light-BG_04282026.pptx`)

> **[MUST] 이 절은 여러 사례를 보고 유추한 관행이 아니라 AWS가 실제로 배포한 디자인
> 시스템 규정임. 임의 해석 없이 원문 그대로 적용할 것.**

**아이콘(Icons) — 원문 그대로 인용 (슬라이드 15)**
> "DO: Use icons at their predefined size, color and format in diagrams. Scale
> icons as needed for use in presentations. [...] DON'T: Crop service icons.
> Flip or rotate icons. Change icon shapes."

- **[MUST]** 아이콘 크기·색상·형태는 사전 정의된 값 그대로 사용할 것. 크롭/반전/
  원본 형태 유지를 원칙으로 합니다. §2 매핑 표의 `fillColor`는 AWS가 카테고리별로
  사전 정의한 색상이므로, 매핑 표에 없는 사전 정의된 색상만 배정할 것.

**그룹(Groups) — 원문 그대로 인용 (슬라이드 14)**
> "DO: Use a generic group type if the presets do not suit your needs. Add a
> custom group if needed. DON'T: Create groups with nonapproved AWS icon(s).
> Resize group icons."

- **[MUST]** Cloud/Region/VPC/Subnet 등 컨테이너(swimlane)는 AWS 프리셋 그룹
  유형을 기본으로 쓰고, 프리셋에 없을 때만 제네릭 그룹으로 대체할 것. 그룹
  아이콘 자체를 리사이즈하지 않습니다 — 010 §2.1의 `startSize` 계층별 고정값
  규칙과 일치함.

**라벨·네이밍(Icon Labels) — 원문 그대로 인용 (슬라이드 17)**
> "AWS service names must fit on no more than two lines. AWS or Amazon should
> always be accompanied by the service name. Lines should never break
> mid-word." / "DO: Break a line after the second word in the service name if
> necessary. DON'T: Use short forms without first mentioning the full service
> name somewhere in the document. [...] Break a line in the middle of a word."

- **[MUST]** 서비스명에는 "AWS" 또는 "Amazon" 접두사를 반드시 함께 표기하고,
  줄바꿈은 단어 중간에서 하지 말며 최대 2줄 이내로 작성할 것. 축약형(예: Amazon
  EC2)을 다이어그램에서 반복 사용할 경우, 같은 문서 내 최초 1회는 전체 명칭을
  명시한 뒤에만 축약형을 쓰십시오.

**화살표·연결선(Arrows) — 원문 그대로 인용 (슬라이드 16)**
> "DO: Use the preset arrows provided in the Elements section. Use straight
> lines and right angles to connect objects wherever possible. [...] DON'T:
> Use anything beside preset or default arrows."

- **[PREFER]** 엣지는 직교(orthogonal) 직선과 직각 연결을 우선하고, 불가피한 경우
  에만 대각선을 허용할 것 — 010 §2.3의 `edgeStyle=orthogonalEdgeStyle` 규칙과
  일치함.

**AWS Cloud 로고 그룹 리전 예외 — 원문 그대로 인용 (슬라이드 25 각주)**
> "In certain AWS Regions (e.g., China), AWS does not own the rights for the
> logo using the letters 'AWS.' Per our guidelines, use the group with the AWS
> logo except in Regions where the AWS logo cannot be used. You may use the
> group with the cloud icon in those cases."

- **[MUST]** 중국 등 AWS 로고 사용이 불가한 리전을 명시적으로 다루는 다이어그램
  에서는 로고형 AWS Cloud 그룹 대신 클라우드 아이콘형 그룹을 사용할 것. 그
  외 일반적인 경우는 로고형 그룹을 기본값으로 유지함.

## 1. AWS 공통 Style 템플릿

- **[MUST]** AWS 리소스 아이콘에는 다음 템플릿을 기반으로 `{COLOR}`와 `{SHAPE}`를 치환하여 사용할 것.

```xml
outlineConnect=0;fontColor=#232F3E;gradientColor=none;fillColor={COLOR};strokeColor=none;
dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;
aspect=fixed;shape={SHAPE};
```

## 2. 아이콘 매핑 테이블

| AWS 리소스 | drawio shape (`{SHAPE}`) | fillColor (`{COLOR}`) | 카테고리 |
|---|---|---|---|
| Internet Gateway | `mxgraph.aws4.internet_gateway` | `#8C4FFF` | Networking |
| NAT Gateway | `mxgraph.aws4.nat_gateway` | `#F58536` | Networking |
| EKS (Cluster/Node) | `mxgraph.aws4.eks` | `#F58536` | Containers |
| ECS / Fargate | `mxgraph.aws4.ecs` | `#F58536` | Containers |
| Lambda | `mxgraph.aws4.lambda` | `#F58536` | Compute |
| EC2 Instance | `mxgraph.aws4.ec2` | `#F58536` | Compute |
| ALB/ELB | `mxgraph.aws4.elastic_load_balancing` | `#8C4FFF` | Networking |
| CloudFront | `mxgraph.aws4.cloudfront` | `#8C4FFF` | Networking |
| API Gateway | `mxgraph.aws4.api_gateway` | `#8C4FFF` | App Integration |
| WAF | `mxgraph.aws4.waf` | `#C925D1` | Security |
| IAM (Role/Policy) | `mxgraph.aws4.iam` | `#C925D1` | Security |
| KMS | `mxgraph.aws4.kms` | `#C925D1` | Security |
| Secrets Manager | `mxgraph.aws4.secrets_manager` | `#C925D1` | Security |
| Route 53 | `mxgraph.aws4.route_53` | `#8C4FFF` | Networking |
| VPN Gateway | `mxgraph.aws4.site_to_site_vpn` | `#8C4FFF` | Networking |
| Transit Gateway | `mxgraph.aws4.transit_gateway` | `#8C4FFF` | Networking |
| MSK (Kafka) | `mxgraph.aws4.managed_streaming_for_kafka` (§1 템플릿 직접 대입하는 대신 §3 resourceIcon 래퍼 필수) | `#8C4FFF` | Analytics |
| SQS | `mxgraph.aws4.sqs` | `#D15100` | App Integration |
| SNS | `mxgraph.aws4.sns` | `#D15100` | App Integration |
| EventBridge | `mxgraph.aws4.eventbridge` | `#D15100` | App Integration |
| WorkSpaces | `mxgraph.aws4.workspaces` | `#5294FF` | End User |
| VPC Endpoint | `mxgraph.aws4.endpoint` | `#8C4FFF` | Networking |
| ENI | `mxgraph.aws4.elastic_network_interface` | `#8C4FFF` | Networking |
| S3 Bucket | `mxgraph.aws4.s3` | `#43B02A` | Storage |
| RDS | `mxgraph.aws4.rds` | `#3334B9` | Database |
| DynamoDB | `mxgraph.aws4.dynamodb` | `#3334B9` | Database |
| ElastiCache | `mxgraph.aws4.elasticache` | `#3334B9` | Database |
| CloudWatch | `mxgraph.aws4.cloudwatch` | `#C925D1` | Management |
| CloudTrail | `mxgraph.aws4.cloudtrail` | `#C925D1` | Management |
| Traditional Server | `mxgraph.aws4.traditional_server` | `#5294FF` | On-Prem (공통) |

## 3. 3rd Party Custom Icon (팀 컨벤션)

- **[MUST]** AWS 기본 서비스가 아닌 오픈소스/서드파티 도구(Jenkins/ArgoCD/Prometheus/Grafana/GitLab 등)의 아이콘 표현 방식은 클라우드 공통 SSOT인 `040-third-party-icon-library.md`를 그대로 적용할 것. 본 문서에서 재나열하지 않습니다.
- **[MUST] resourceIcon 래퍼 패턴**: MSK(Kafka)처럼 `shape=mxgraph.aws4.{SHAPE}` 직접 지정으로 렌더링되지 않는 아이콘은 다음 패턴을 사용할 것.
  - `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{SHAPE};` (`{SHAPE}`는 위 아이콘 매핑 테이블 값)
  - 예시(검증됨): MSK(Kafka) → `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.managed_streaming_for_kafka;`

## 4. 컨테이너 색상 (AWS)

- **[MUST]** AWS Cloud/Region/VPC/Subnet/Auto Scaling Group 컨테이너 색상은 010 §4 "색상 팔레트 (클라우드 공통)" 표를 그대로 적용할 것. SSOT는 010이며 본 절에서 재나열하지 않습니다.

## 5. 아이콘-리소스 정확성 가드레일 (Icon Fidelity)

- **[MUST] 정확한 리소스 타입 기반 아이콘 매핑**: 리소스명이나 개념이 AWS 관리형 서비스 이름과 비슷하다는 이유만으로 해당 서비스 아이콘으로 대체하는 대신 정확한 대안을 적용할 것. (예: 온프레미스 AD 연동 자체 관리형 Windows EC2 VDI 풀을 `WorkSpaces` 아이콘으로 표현하면, 실제로는 사용하지 않는 Amazon WorkSpaces 관리형 서비스를 쓰는 것처럼 오인시킬 수 있으므로 주의할 것.) 아이콘은 실제 Terraform 리소스 타입(예: `aws_workspaces_*` vs `aws_instance`+`aws_autoscaling_group`)과 정확히 일치할 때만 사용하고, 다르면 EC2 등 실제 리소스 타입에 맞는 아이콘을 쓰십시오. 매핑 테이블에 정확히 대응하는 아이콘이 없으면 억지로 유사 아이콘을 끼워 맞추는 대신 텍스트 노트(rect+텍스트)로 대체할 것.
