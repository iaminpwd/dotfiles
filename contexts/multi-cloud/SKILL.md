---
name: multi-cloud
description: |
  AWS-Azure 멀티 클라우드 네트워크 연동 및 하이브리드 아키텍처 스킬.
  VPN, Peering, Transit Gateway, ExpressRoute, 크로스 클라우드 IAM, DNS 통합.
---
# multi-cloud Skill

이 스킬은 AWS와 Azure 리소스를 혼합하여 사용하는 하이브리드/멀티 클라우드 아키텍처 설계 시 발동됩니다.
단일 클라우드 작업일 경우에는 개별 클라우드 폴더(aws, azure)에 진입하여 작업하고, 서로 교차 참조하지 않도록 주의하십시오.

## 작업 유형별 참조 문서 라우팅

| 작업 유형 | 참조 문서 |
|-----------|----------|
| 멀티 클라우드 연동 및 하이브리드 코어 아키텍처 | references/010-multi-cloud-core.md |

## 동적 지식 융합 가이드 (Dynamic Cross-Cloud Routing)

- 괄호 안의 예시(EKS 등)에 국한되지 않습니다. 질문에 AWS와 관련된 어떠한 서비스나 키워드라도 포함되어 있다면, 반드시 전역 등록된 `aws` 스킬 문서를 우선 확인하여 코어 룰을 수집하십시오.
- 마찬가지로 질문에 Azure와 관련된 어떠한 서비스나 키워드라도 포함되어 있다면, 반드시 전역 등록된 `azure` 스킬 문서를 우선 확인하여 코어 룰을 수집하십시오.

## [MUST] 작업 시작 전 필수 사전 분석

Terraform, Ansible, Bicep, 쉘 스크립트 등 멀티 클라우드 연동 코드를 신규 작성하거나 수정을 시작하기 전에, **어떠한 도구 실행이나 코드 작성을 수행하기 전** 반드시 아래 절차를 따르십시오.

1. 본 스킬 문서 내 "작업 유형별 참조 문서 라우팅" 테이블에서 요청받은 태스크와 일치하는 대상 참조 문서를 찾으십시오.
2. 해당 참조 문서(예: `references/010-multi-cloud-core.md` 등)를 `view_file` 도구로 먼저 읽어 그 안에 명시된 설계 및 보안 표준을 파악한 후 코딩에 착수하십시오.

## [MUST] IaC 코드 수정 후 필수 후속 동작

Terraform, Ansible, Bicep, 쉘 스크립트 등 멀티 클라우드 연동 코드를 신규 작성하거나 수정한 경우, **작업 완료를 선언하기 전에** 반드시 아래 절차를 따르십시오.

1. `Pre-Flight Check` 스킬의 `SKILL.md`를 `view_file` 도구로 직접 읽으십시오.
2. 해당 SKILL.md에 명시된 `pre-flight-check.sh` 연결 및 실행 절차를 그대로 수행하십시오.

