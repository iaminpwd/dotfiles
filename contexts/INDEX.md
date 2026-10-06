# Contexts Index

> 자동 생성 문서입니다. 직접 편집하지 말고 아래 명령으로 재생성하십시오:
> `bash bin/utils/generate-context-index.sh > contexts/INDEX.md`
>
> 각 워크스페이스 SKILL.md의 라우팅 테이블을 그대로 모은 색인이므로, 실제 조항 내용은
> 반드시 해당 참조 문서를 직접 여십시오. 전체 이론적 배경은 [README.md](README.md) 참고.

## aiops

AIOps 텔레메트리·Closed-Loop 자동화 검증 스킬. TelemetryCollectorConfig/ClosedLoopPolicy,

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_

## aws

AWS 인프라 작업 스킬. VPC, EC2, S3, RDS, Lambda, EKS, IAM, CloudFormation, Terraform,

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_

## containers

컨테이너 이미지 엔지니어링 스킬. Dockerfile/OCI 이미지 빌드, 멀티스테이지,

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_

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

Kubernetes(k8s) 클러스터 및 컨테이너 오케스트레이션 스킬. Pod, Deployment, Service, Ingress, CNI,

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_

## observability

클라우드/K8s 전반의 관측성(Observability) 설계 스킬. 메트릭·로그·트레이스 3대 요소,

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_

## pre-flight-check

Terraform, Ansible, Helm, Dockerfile 및 셸 자동화 변경의 검증 명령·프로필·결과를 확인할 때 사용.

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_

## prompt-architect

AI 프롬프트와 룰북(AGENTS.md, SKILL.md)을 작성·검토·간소화할 때 사용하는 검증 스킬.

_(라우팅 테이블 없음 — SKILL.md 단일 문서)_
