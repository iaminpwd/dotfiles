# Contexts Index

> 자동 생성 문서입니다. 직접 편집하지 말고 아래 명령으로 재생성하십시오:
> `bash bin/utils/generate-context-index.sh > contexts/INDEX.md`
>
> 각 워크스페이스 SKILL.md의 라우팅 테이블을 그대로 모은 색인이므로, 실제 조항 내용은
> 반드시 해당 참조 문서를 직접 여십시오. 전체 이론적 배경은 [README.md](README.md) 참고.

## aiops

AIOps 텔레메트리·Closed-Loop 자동화 검증 스킬. TelemetryCollectorConfig/ClosedLoopPolicy, 동적 이상 임계치, RAG/프라이빗 LLM용 PII 마스킹, AIOps 커밋 훅과 회귀 테스트에 사용.

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_

## aws

AWS 인프라 작업 스킬. VPC, EC2, S3, RDS, Lambda, EKS, IAM, CloudFormation, Terraform, 서버리스, CI/CD, FinOps 등 AWS 전반.

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_

## containers

컨테이너 이미지 엔지니어링 스킬. Dockerfile/OCI 이미지 빌드, 멀티스테이지, 이미지 하드닝(non-root, distroless), SBOM/서명/취약점 스캔 등 공급망 보안, 레지스트리 태깅 및 라이프사이클, 컨테이너 런타임 트러블슈팅.

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_

## dotfiles

이 저장소의 bootstrap, Ansible, Stow, mise, shell 설정, hooks와 회귀 검증을 변경할 때 사용하는 로컬 스킬.

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_

## drawio-gen

인프라 및 시스템 아키텍처를 실제 .drawio XML로 생성·수정할 때 사용하는 스킬.

| 작업 유형 | 참조 문서 |
|---|---|
| DrawIO XML 공통 포맷·계층·엣지·라벨 | references/010-drawio-xml-standard.md |
| 좌표·크기·정렬·waypoint 계산 | references/015-layout-calculation-standard.md |
| AWS 아이콘 스타일 | references/020-aws-icon-style-library.md |
| Azure 아이콘 스타일 | references/030-azure-icon-style-library.md |
| OpenStack 아이콘·도형·색상 계약 | references/035-openstack-icon-style-library.md |
| OSS/서드파티 아이콘 | references/040-third-party-icon-library.md |
| 제목·범례·라벨·타이포그래피 | references/050-readability-standard.md |
| 완료 조건·기계 검증 | references/090-validation-standard.md |
| 레이아웃 계산·검증 구현 | scripts/layout_toolkit.py |

## k8s

Kubernetes(k8s) 클러스터 및 컨테이너 오케스트레이션 스킬. Pod, Deployment, Service, Ingress, CNI, PVC, StatefulSet, ArgoCD, Flux, Prometheus, Grafana, HPA, VPA, RBAC, OPA, 멀티테넌시. 매니페스트 작성·검토, 클러스터 정책과 트러블슈팅에 사용. 관리형 클러스터에서도 워크로드는 이 스킬로 다루고, 클라우드 IAM·노드·네트워크 변경이 있을 때만 클라우드 스킬을 추가 참조함. Pod Security Admission(PSA), securityContext, PrometheusRule 등 K8s CRD 및 어드미션 정책도 다룸.

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_

## observability

클라우드/K8s 전반의 관측성(Observability) 설계 스킬. 메트릭·로그·트레이스 3대 요소, SLI/SLO/에러 버짓, 알람 설계, 구조화 로깅, OpenTelemetry 분산 추적, Grafana/Datadog 등 대시보드 및 SaaS 통합.

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_

## pre-flight-check

이 저장소의 pre-flight 검증 대상, 프로필, 실행 명령과 WARNING/SKIP/실패 결과를 해석할 때 사용하는 로컬 스킬.

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_

## prompt-architect

AI 프롬프트와 룰북(AGENTS.md, SKILL.md)을 작성·검토·간소화할 때 사용하는 검증 스킬.

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_
