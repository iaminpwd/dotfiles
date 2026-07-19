---
name: multi-cloud
description: |
  AWS-Azure 멀티 클라우드 네트워크 연동 및 하이브리드 아키텍처 스킬.
  VPN, Peering, Transit Gateway, ExpressRoute, 크로스 클라우드 IAM, DNS 통합.
---
# multi-cloud Skill

이 스킬은 AWS와 Azure 리소스를 혼합하여 사용하는 하이브리드/멀티 클라우드 아키텍처 설계 시 발동됩니다.
단일 클라우드 작업일 경우 개별 클라우드 스킬(aws, azure)로 진입하여 작업하십시오.

## 1. 작업 유형별 참조 문서 라우팅 (SSOT)

| 작업 유형 | 참조 문서 |
|---|---|
| 멀티 클라우드 연동 및 하이브리드 코어 아키텍처 | references/010-multi-cloud-core.md |

### 동적 지식 융합 가이드 (Dynamic Cross-Cloud Routing)
- 질문에 AWS와 연동되는 리소스나 키워드가 포함될 경우, 반드시 `aws` 스킬 룰북들을 교차 조회하여 코어 룰을 확보하십시오.
- 질문에 Azure와 연동되는 리소스나 키워드가 포함될 경우, 반드시 `azure` 스킬 룰북들을 교차 조회하여 코어 룰을 확보하십시오.

## 2. 작업 프로세스 제약 (Operational Gate)

- **[MUST] 사전 룰북 분석**: 멀티 클라우드 연동 코드(Terraform, Ansible 등) 작성을 시작하기 전, 반드시 라우팅 테이블에서 대상 룰북을 찾아 `view_file`로 먼저 읽어 아키텍처 표준을 파악하십시오.
- **[MUST] 사후 통합 검증 (Pre-Flight Check)**: 코드 작성을 완료한 직후, 작업을 완료 선언하기 전에 반드시 [Pre-Flight Check SKILL.md](file:///home/ubuntu/dotfiles/contexts/pre-flight-check/SKILL.md)를 읽고 `pre-flight-check.sh` 스크립트를 실행하여 정량 검증을 완료하십시오.
