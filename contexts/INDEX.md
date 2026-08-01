# Contexts Index

> 자동 생성 문서입니다. 직접 편집하지 말고 아래 명령으로 재생성하십시오:
> `bash bin/utils/generate-context-index.sh > contexts/INDEX.md`
>
> 각 워크스페이스 SKILL.md의 라우팅 테이블을 그대로 모은 색인이므로, 실제 조항 내용은
> 반드시 해당 참조 문서를 직접 여십시오. 전체 이론적 배경은 [README.md](README.md) 참고.

## aiops

AIOps 자동화 파이프라인 및 SRE 스킬. 동적 임계치 시계열 이상 탐지, 탐지→진단→대응→검증 Closed-Loop 자동화,

| 작업 유형 | 참조 문서 |
|---|---|
| AIOps 프로젝트 및 자동화 파이프라인 기획 | references/005-project-planning-template.md |
| 보안(SecOps), 규정 준수(ISMS-P/비식별화) | references/020-security-compliance.md |
| 비용 분석(FinOps), DORA 메트릭 | references/030-finops-optimization.md |
| 엣지 케이스, 복원력, 카오스 엔지니어링 | references/040-resiliency-chaos-standard.md |
| IaC 및 GitOps 파이프라인 아키텍처 | references/050-iac-standard.md |
| AI 에이전트 RAG, Self-healing 워크플로우 | references/060-agent-logic.md |
| 장애 분석(RCA), 트러블슈팅, Blameless 사후 분석 | references/100-incident-response.md |
| Closed-Loop 명세 및 RAG 참조 파이프라인 코드 예시 | examples/ |
| 텔레메트리 파이프라인 및 동적 임계치 정량 검증 도구 | scripts/ |
| scripts/examples 회귀 테스트 실행 | tests/run.sh |

## aws

AWS 인프라 작업 스킬. VPC, EC2, S3, RDS, Lambda, EKS, IAM, CloudFormation, Terraform,

| 작업 유형 | 참조 문서 |
|---|---|
| 프로젝트 기획 및 아키텍처 설계 | references/005-project-planning-template.md |
| IAM 정책 / 시크릿 관리 감사 | references/020-security-compliance.md |
| 네트워크 설계 및 멀티계정 보안 | references/025-cloud-security.md |
| 비용 최적화 및 FinOps | references/030-finops-optimization.md |
| 쉘 스크립팅 및 자동화 스크립트 | references/040-automation-scripting.md |
| Terraform 및 Ansible IaC 코드 | references/050-iac-standard.md |
| EKS 및 Helm 오케스트레이션 | references/060-eks-standard.md |
| Lambda 및 API Gateway 서버리스 | references/070-serverless-standard.md |
| RDS 및 DynamoDB 데이터베이스 | references/080-database-standard.md |
| CI/CD 파이프라인 및 Day-2 운영 | references/090-day2-operations.md |
| 장애 대응 및 Post-Mortem 분석 | references/100-incident-response.md |

## azure

Azure 인프라 작업 스킬. VNet, VM, AKS, Azure Functions, CosmosDB, Azure SQL,

| 작업 유형 | 참조 문서 |
|---|---|
| 프로젝트 기획 및 아키텍처 설계 | references/005-project-planning-template.md |
| IAM/RBAC 정책 / 시크릿 관리 감사 | references/020-security-compliance.md |
| 네트워크 설계 및 멀티계정 환경 | references/025-cloud-security.md |
| 비용 최적화 및 FinOps | references/030-finops-optimization.md |
| 쉘 스크립팅 및 자동화 태스크 | references/040-automation-scripting.md |
| Terraform 및 Ansible IaC | references/050-iac-standard.md |
| AKS 및 Helm 오케스트레이션 | references/060-aks-standard.md |
| Azure Functions 서버리스 | references/070-serverless-standard.md |
| Azure SQL 및 CosmosDB | references/080-database-standard.md |
| CI/CD 및 프로덕션 배포 | references/090-day2-operations.md |
| 장애 트러블슈팅 및 인시던트 대응 | references/100-incident-response.md |

## containers

컨테이너 이미지 엔지니어링 스킬. Dockerfile/OCI 이미지 빌드, 멀티스테이지,

| 작업 유형 | 참조 문서 |
|---|---|
| Dockerfile 작성 및 멀티스테이지 빌드 | references/010-containers-core.md |
| 이미지 하드닝 (non-root, distroless, RO rootfs) | references/020-image-hardening-standard.md |
| SBOM, 이미지 서명, 취약점 스캔 (공급망 보안) | references/030-supply-chain-security-standard.md |
| 레지스트리 태깅 규칙 및 라이프사이클 정책 | references/040-registry-lifecycle-standard.md |
| 컨테이너 런타임 장애 대응 (OOMKilled, CrashLoop 등) | references/100-incident-response.md |

## dotfiles

개인 로컬 환경 및 dotfiles 시스템 셋업 스킬. bootstrap.sh, ansible, zsh, bash, stow, mise,

| 작업 유형 | 참조 문서 |
|---|---|
| 이 저장소 작업의 계획서·핸드오프 설계도 작성 | references/020-project-planning-template.md |
| dotfiles 아키텍처 및 핵심 구조 | references/030-dotfiles-core-standard.md |
| 도구 및 패키지 관리 (apt, mise 등) | references/040-toolchain-management-standard.md |
| 시크릿 관리, 권한 설정, 로컬 보안 정책 | references/050-dotfiles-security-standard.md |
| 환경 셋업 오류 및 런타임 트러블슈팅 | references/060-troubleshooting-standard.md |

## drawio-gen

인프라 및 시스템 아키텍처 다이어그램 생성(draw.io) 스킬. "다이어그램 그려줘", "구성도 만들어줘", "도식화해줘",

| 작업 유형 | 참조 문서 |
|---|---|
| 근거 충실성 원칙 (Anti-Hallucination) | references/005-fidelity-anti-hallucination-standard.md |
| DrawIO XML 공통 포맷 규격 | references/010-drawio-xml-standard.md |
| 레이아웃 계산 및 배치 검증 (좌표/크기/정렬/waypoint) | references/015-layout-calculation-standard.md |
| AWS 리소스 아이콘 스타일 | references/020-aws-icon-style-library.md |
| Azure 리소스 아이콘 스타일 | references/030-azure-icon-style-library.md |
| OpenStack 리소스 아이콘 스타일 | references/035-openstack-icon-style-library.md |
| 서드파티/OSS 도구 아이콘 (클라우드 공통) | references/040-third-party-icon-library.md |
| 가독성 (범례/제목/라벨 줄바꿈/타이포그래피) | references/050-readability-standard.md |
| 검증 및 수락 기준 (완료 조건/검증 스크립트) | references/090-validation-standard.md |
| 레이아웃 계산 공용 코드 (격자/스택/겹침검사) | scripts/layout_toolkit.py |

## k8s

Kubernetes(k8s) 클러스터 및 컨테이너 오케스트레이션 스킬. Pod, Deployment, Service, Ingress, CNI,

| 작업 유형 | 참조 문서 |
|---|---|
| 파드 / Deployment / ConfigMap 등 기본 K8s 리소스 작업 | references/010-k8s-core.md |
| 네트워크 리소스 (Ingress, Service, CNI) | references/020-networking-standard.md |
| 스토리지 (PVC/PV) 및 StatefulSet | references/030-storage-stateful-standard.md |
| CI/CD, GitOps (ArgoCD, Flux) | references/040-cicd-gitops-standard.md |
| Prometheus Operator CRD 수집 문법 (ServiceMonitor 등) | references/050-observability-standard.md |
| SLI/SLO, 알람 설계, 로깅, 분산 추적 등 관측성 일반 원칙 | `observability 스킬(SKILL.md)` (별도 스킬) |
| 오토스케일링 (HPA, VPA) 및 FinOps | references/060-autoscaling-finops-standard.md |
| 클러스터 보안 (RBAC, OPA, NetworkPolicy) | references/070-advanced-security-standard.md |
| 플랫폼 엔지니어링, 멀티테넌시 | references/080-platform-engineering-standard.md |
| K8s 장애 대응, 트러블슈팅, RCA | references/100-incident-response.md |

## multi-cloud

서로 다른 환경을 잇는 네트워크 연동 스킬. 클라우드 간(AWS-Azure) 연동뿐 아니라

| 작업 유형 | 참조 문서 |
|---|---|
| 멀티 클라우드 연동 및 하이브리드 코어 아키텍처 | references/010-multi-cloud-core.md |

## observability

클라우드/K8s 전반의 관측성(Observability) 설계 스킬. 메트릭·로그·트레이스 3대 요소,

| 작업 유형 | 참조 문서 |
|---|---|
| 프로젝트 기획 및 아키텍처 설계 | references/005-project-planning-template.md |
| 관측성 기본 원칙, SLI/SLO, Error Budget | references/010-observability-core.md |
| 메트릭 설계 및 알람 (PromQL, CloudWatch, Azure Monitor) | references/020-metrics-alerting-standard.md |
| 구조화 로깅 및 로그 파이프라인 (Loki/ELK/CloudWatch Logs) | references/030-logging-standard.md |
| 분산 추적 (OpenTelemetry) | references/040-tracing-standard.md |
| 대시보드 설계 및 SaaS 연동 (Grafana, Datadog) | references/050-dashboard-saas-standard.md |

## openstack

OpenStack 프라이빗 클라우드 작업 스킬. Nova, Neutron, Cinder, Swift, Glance, Keystone,

| 작업 유형 | 참조 문서 |
|---|---|
| 프로젝트 기획 및 아키텍처 설계 | references/005-project-planning-template.md |
| Keystone RBAC / Barbican 시크릿 관리 감사 | references/020-security-compliance.md |
| Neutron 네트워크 설계 및 멀티프로젝트/도메인 보안 | references/025-cloud-security.md |
| Neutron SDN 백엔드(OVN/ML2) 및 라우팅 아키텍처 | references/026-networking-standard.md |
| 하이브리드/엣지 연결(VPNaaS, BGP, 페더레이션) | references/027-hybrid-connectivity-standard.md |
| 쿼터 관리 및 FinOps (CloudKitty 차지백) | references/030-finops-optimization.md |
| 쉘 스크립팅 및 openstack CLI 자동화 | references/040-automation-scripting.md |
| Terraform / Heat HOT / Ansible IaC 코드 | references/050-iac-standard.md |
| Magnum 및 Helm 오케스트레이션 (K8s) | references/060-magnum-k8s-standard.md |
| Ironic 베어메탈 및 Nova 하이퍼바이저 운영 | references/070-compute-baremetal-standard.md |
| Trove 및 자체 관리 데이터베이스 | references/080-database-standard.md |
| Swift 객체 스토리지 설계 (내구성 정책/S3 호환) | references/085-object-storage-standard.md |
| 컨트롤플레인 수명주기 및 Day-2 운영 | references/090-day2-operations.md |
| 장애 대응 및 Post-Mortem 분석 | references/100-incident-response.md |

## pre-flight-check

인프라 및 자동화 코드에 대한 정량적 사전 검증(Pre-Flight Check) 및 린트/정적 분석 파이프라인 스킬임.

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_

## prompt-architect

전역 AI 프롬프트 엔지니어링, 룰북(AGENTS.md, SKILL.md) 작성, 범용 쉘 스크립트 작성 표준 지침.

| 작업 유형 | 참조 문서 |
|---|---|
| AI 프롬프트 설계(Meta-Prompting) 마스터 가이드 | references/030-prompt-engineering-standard.md |
| 범용 AI 프롬프트 작성·수정·최적화 표준 | references/040-general-prompt-authoring-standard.md |
| 룰북 조항 추가·검토·삭제 가이드 | references/050-rule-provenance-standard.md |
| 쉘 스크립팅(bash/zsh) 범용 표준 | references/020-shell-scripting-standard.md |
