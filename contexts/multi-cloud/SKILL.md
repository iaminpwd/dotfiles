---
name: multi-cloud
description: |
  서로 다른 환경을 잇는 네트워크 연동 스킬. 클라우드 간(AWS-Azure) 연동뿐 아니라
  온프레미스·데이터센터와 클라우드를 잇는 하이브리드 연결도 이 스킬입니다.
  전용선(Direct Connect, ExpressRoute), VPN, Peering, Transit Gateway,
  크로스 환경 IAM 및 DNS 통합. 단일 클라우드 내부 작업이 아니라 두 환경의
  경계를 잇는 요청이면 이 스킬을 사용하십시오.
reviewed: 2026-07-27
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

- **[MUST] 사전 룰북 및 연관 참조 연쇄 분석 (Recursive Reference Check)**: 멀티 클라우드 연동 코드(Terraform, Ansible 등) 작성을 시작하기 전, 반드시 라우팅 테이블에서 대상 룰북을 찾아 먼저 읽으십시오. 또한 해당 룰북 내에 명시된 연관 참조 문서(`references:` 항목 또는 텍스트 내 참조 문서)가 존재하는 경우 연쇄적으로 읽되, 이미 읽은 파일은 중복 방문하지 않는 방문 목록(Visited Set) 규칙을 준수하여 무한 루프 없이 연결된 모든 연관 룰북을 빠짐없이 수집하십시오.
- **[MUST] 사후 통합 검증 (Pre-Flight Check)**: 코드 작성을 완료한 직후, 작업을 완료 선언하기 전에 `pre-flight-check` 스킬을 호출하여 `pre-flight-check.sh` 정량 검증을 통과시키십시오. 스킬 호출이 불가능한 환경에서는 `~/dotfiles/contexts/pre-flight-check/SKILL.md`를 절대 경로로 읽어 동일 절차를 수행하십시오.
