---
role: Infrastructure Diagram Generator
priority: high
trigger: AWS 관련 drawio XML 파일을 생성하거나 수정할 때 적용
references:
  - contexts/drawio-gen/references/010-drawio-xml-standard.md
  - contexts/drawio-gen/references/040-third-party-icon-library.md
reviewed: 2026-07-21
---
# AWS 아이콘 스타일 라이브러리 매핑

본 모듈은 AWS 아키텍처 다이어그램 생성 시 사용되는 아이콘들의 Shape 속성 및 색상 매핑 가이드입니다.

## 1. AWS 공통 Style 템플릿

- **[MUST]** AWS 리소스 아이콘에는 다음 템플릿을 기반으로 `{COLOR}`와 `{SHAPE}`를 치환하여 사용하십시오.

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
| MSK (Kafka) | `mxgraph.aws4.managed_streaming_for_kafka` (§1 템플릿 직접 대입 금지, §3 resourceIcon 래퍼 필수) | `#8C4FFF` | Analytics |
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

- **[MUST]** AWS 기본 서비스가 아닌 오픈소스/서드파티 도구(Jenkins/ArgoCD/Prometheus/Grafana/GitLab 등)의 아이콘 표현 방식은 클라우드 공통 SSOT인 `040-third-party-icon-library.md`를 그대로 적용하십시오. 본 문서에서 재나열하지 않습니다.
- **[MUST] resourceIcon 래퍼 패턴**: MSK(Kafka)처럼 `shape=mxgraph.aws4.{SHAPE}` 직접 지정으로 렌더링되지 않는 아이콘은 다음 패턴을 사용하십시오.
  - `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{SHAPE};` (`{SHAPE}`는 위 아이콘 매핑 테이블 값)
  - 예시(검증됨): MSK(Kafka) → `shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.managed_streaming_for_kafka;`

## 4. 컨테이너 색상 (AWS)

- **[MUST]** AWS Cloud/Region/VPC/Subnet/Auto Scaling Group 컨테이너 색상은 010 §4 "색상 팔레트 (클라우드 공통)" 표를 그대로 적용하십시오. SSOT는 010이며 본 절에서 재나열하지 않습니다.

## 5. 아이콘-리소스 정확성 가드레일 (Icon Fidelity)

- **[MUST] 이름 유사성만으로 아이콘 대체 금지**: 리소스명이나 개념이 AWS 관리형 서비스 이름과 비슷하다는 이유만으로 해당 서비스 아이콘을 대체 사용하지 마십시오. (예: 온프레미스 AD 연동 자체 관리형 Windows EC2 VDI 풀을 `WorkSpaces` 아이콘으로 표현하면, 실제로는 사용하지 않는 Amazon WorkSpaces 관리형 서비스를 쓰는 것처럼 오인시킵니다.) 아이콘은 실제 Terraform 리소스 타입(예: `aws_workspaces_*` vs `aws_instance`+`aws_autoscaling_group`)과 정확히 일치할 때만 사용하고, 다르면 EC2 등 실제 리소스 타입에 맞는 아이콘을 쓰십시오. 매핑 테이블에 정확히 대응하는 아이콘이 없으면 억지로 유사 아이콘을 끼워 맞추지 말고 텍스트 노트(rect+텍스트)로 대체하십시오.
