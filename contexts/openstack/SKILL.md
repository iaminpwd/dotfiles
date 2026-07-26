---
name: openstack
description: |
  OpenStack 프라이빗 클라우드 작업 스킬. Nova, Neutron, Cinder, Swift, Glance, Keystone,
  Heat, Octavia, Barbican, Magnum, Trove, Ironic, Ceph 백엔드, Terraform/Ansible IaC,
  Kolla-Ansible 컨트롤플레인 운영, 쿼터/FinOps 등 OpenStack 전반.
reviewed: 2026-07-23
---
# openstack Operations Skill

이 스킬은 OpenStack 프라이빗 클라우드 관련 인프라 기획, 네트워크, 컨테이너, 베어메탈 및 보안 제어 작업 시 발동됩니다.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

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

* **기본 아키텍처 원칙**: references/010-openstack-core.md
* **보안 및 시크릿 규정**: references/020-security-compliance.md

## 2. 작업 프로세스 제약 (Operational Gate)

- **[MUST] 사전 룰북 및 연관 참조 연쇄 분석 (Recursive Reference Check)**: 인프라 코드(Terraform, Heat, Ansible 등) 작성을 시작하기 전, 반드시 라우팅 테이블에서 대상 룰북을 찾아 먼저 읽으십시오. 또한 해당 룰북 내에 명시된 연관 참조 문서(`references:` 항목 또는 텍스트 내 참조 문서)가 존재하는 경우 연쇄적으로 읽되, 이미 읽은 파일은 중복 방문하지 않는 방문 목록(Visited Set) 규칙을 준수하여 무한 루프 없이 연결된 모든 연관 룰북을 빠짐없이 수집하십시오.
- **[MUST] 사후 통합 검증 (Pre-Flight Check)**: 코드 작성을 완료한 직후, 작업을 완료 선언하기 전에 `pre-flight-check` 스킬을 호출하여 `pre-flight-check.sh` 정량 검증을 통과시키십시오. 스킬 호출이 불가능한 환경에서는 `~/dotfiles/contexts/pre-flight-check/SKILL.md`를 절대 경로로 읽어 동일 절차를 수행하십시오.
