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
