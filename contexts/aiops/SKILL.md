---
name: aiops
description: |
  AIOps 텔레메트리·Closed-Loop 자동화 검증 스킬. TelemetryCollectorConfig/ClosedLoopPolicy,
  동적 이상 임계치, RAG/프라이빗 LLM용 PII 마스킹, AIOps 커밋 훅과 회귀 테스트에 사용.
---
# aiops Skill

AIOps 자동화와 텔레메트리 관련 작업에 사용한다. 일반 AIOps/SRE/FinOps/RAG 설계 지식은 현재 코드와 공식 문서를 기준으로 판단하고, 이 저장소가 실제로 강제하는 검증 계약만 아래에 둔다.

## 저장소 검증 계약

- AIOps 스크립트·예제·커밋 훅의 동작을 변경하면 `bash contexts/aiops/tests/run.sh`를 실행한다.
- `bin/hooks/plugins/aiops-check.sh`는 스테이징된 YAML/YML에 `ClosedLoopPolicy` 또는 `TelemetryCollectorConfig`가 있을 때만 활성화하고, 같은 커밋의 YAML/YML/JSON/Terraform 파일을 격리된 임시 디렉터리에서 `contexts/aiops/scripts/validate-telemetry-schema.sh`로 검사한다.
- 텔레메트리 검증기는 평문 시크릿 대입을 차단하되 로그에 시크릿 원문을 출력하지 않는다. `yamllint`가 없으면 YAML 문법 검사가 미실행임을 WARNING으로 드러내고, 평문 시크릿 검사는 계속 수행한다.
- `eval-anomaly-threshold.py`는 빈 입력과 정상 입력의 반환 키 집합을 동일하게 유지하고, 알려진 데이터셋의 임계치 계산을 회귀 테스트로 고정한다.
- `examples/anomaly-rag-pipeline.py`의 PII 마스킹은 주민번호·카드·계좌·전화·이메일과 중첩 payload를 대상으로 하며, 원문 민감값 유출과 일반 로그 과잉 마스킹을 모두 회귀 테스트로 막는다.
- 실제 변경 파일의 quick/full 검사와 WARNING/SKIP 해석은 `contexts/pre-flight-check/SKILL.md`를 따른다.
