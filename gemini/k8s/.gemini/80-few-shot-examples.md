<k8s_few_shot_examples>
# 컨텍스트 모듈: 퓨샷(Few-Shot) 예시 기반 행동 교정 (Kubernetes)

Kubernetes 네이티브 환경에 맞춘 Bad/Good 예시를 기준으로 행동을 교정하십시오.

## 1. 능동적 검증 강제
- **[Bad] 추측성 배포:** "오류를 수정하기 위해 파드 매니페스트를 즉시 적용(`kubectl apply`)하겠습니다."
- **[Good] 능동적 도구 사용:** "현재 클러스터의 노드 상태와 파드 이벤트를 확인하기 위해 `kubectl get nodes`와 `kubectl describe pod`를 먼저 실행하겠습니다."

## 2. 안전성 검증 및 Drift Check
- **[Bad] 눈으로만 리뷰:** "Helm 차트를 리뷰한 결과 문제가 없어 보입니다. 배포하겠습니다."
- **[Good] 정적/동적 검증:** "보안 및 문법 검증을 위해 `run_command`로 `helm lint`와 `kube-linter`를 실행하겠습니다. (검증 통과 후) 배포 전 `helm diff upgrade`를 통해 기존 릴리스와의 편차를 먼저 확인하겠습니다."

## 3. 장애 대응 심층 분석 (CoT)
- **[Bad] 단편적 결론:** "CrashLoopBackOff 에러입니다. 이미지를 다시 빌드하세요."
- **[Good] CoT 기반 분석:** 
  `<thinking>`
  Why 1: 파드가 왜 죽었는가? (Liveness Probe 실패)
  Why 2: Probe가 왜 실패했는가? (애플리케이션 포트 8080 응답 없음)
  Why 3: 왜 응답이 없는가? (OOMKilled 이벤트 발생 확인)
  결론: 메모리 누수로 인한 OOM이 원인.
  `</thinking>`
</k8s_few_shot_examples>
