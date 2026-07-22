---
role: Infrastructure Diagram Generator
priority: high
trigger: AWS/Azure 네이티브 리소스가 아닌 OSS/서드파티 도구 아이콘을 drawio XML에 표현할 때 적용 (클라우드 공통 SSOT)
references:
  - contexts/drawio-gen/references/010-drawio-xml-standard.md
reviewed: 2026-07-21
---
# 서드파티/OSS 도구 아이콘 라이브러리 (클라우드 공통)

본 모듈은 AWS/Azure 어느 쪽에도 종속되지 않는 서드파티 도구 아이콘 표현 규칙의 단일 진실 공급원(SSOT)입니다. 020(AWS)/030(Azure) 문서는 본 문서를 참조하며 표를 재나열하지 않습니다.

## 1. 이미지형 스타일 템플릿

- **[MUST]** AWS/Azure 기본 서비스가 아닌 아래 오픈소스/서드파티 도구는 밋밋한 대체 아이콘 대신 아래 표에 지정된 방식을 그대로 적용하십시오.
- **[MUST] 이미지형 스타일 템플릿** (Jenkins/ArgoCD/Prometheus/Grafana에 적용): `shape=image;html=1;verticalAlign=top;verticalLabelPosition=bottom;labelBackgroundColor=#ffffff;imageAspect=0;aspect=fixed;image={URL};`

| 리소스 | 적용 방식 |
|---|---|
| Jenkins | 이미지형, `{URL}` = `https://upload.wikimedia.org/wikipedia/commons/e/e9/Jenkins_logo.svg` |
| ArgoCD | 이미지형, `{URL}` = `https://argo-cd.readthedocs.io/en/stable/assets/logo.png` |
| Prometheus | 이미지형, `{URL}` = `https://upload.wikimedia.org/wikipedia/commons/3/38/Prometheus_software_logo.svg` |
| Grafana | 이미지형, `{URL}` = `https://upload.wikimedia.org/wikipedia/commons/3/3b/Grafana_icon.svg` |
| GitLab | **예외** — 이미지형 템플릿에 대입 금지. style 전체를 다음으로 교체: `shape=mxgraph.ibm_cloud.logo--gitlab;fillColor=#E24329;strokeColor=none;html=1;verticalLabelPosition=bottom;verticalAlign=top;labelBackgroundColor=#ffffff;` |

## 2. 표에 없는 도구

- **[MUST]** 위 표에 없는 도구는 임의로 URL을 창작하지 말고, `shape=rect`에 텍스트만 넣은 대체 아이콘을 사용하거나 사용자에게 실제 사용 여부와 로고 출처를 확인하십시오.
