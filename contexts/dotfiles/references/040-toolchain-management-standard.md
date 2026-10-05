---
trigger: 패키지 설치나 mise 도구·버전 선언을 변경할 때 참조.
---
# 도구와 버전 관리

- **[MUST] 도구 선언 원본:** `stow/mise/.config/mise/config.toml`에 선언한다. Stow 연결 후 `~/.config/mise/config.toml`로 노출되며 저장소 밖에서도 도구가 해석된다. `~/.mise.toml`에 분산하지 않는다.
- **[MUST] 백엔드 선택:** 직접 pipx 설치 대신 mise 선언을 사용한다. 네이티브 백엔드가 있으면 도구명, 없으면 `"pipx:<tool_name>"`을 사용한다. 신규 도구는 `mise registry`로 백엔드를 확인한다.
- **[MUST] 버전 고정:** 본체 바이너리와 인프라 린터는 특정 버전으로 고정한다. 보안 DB·플러그인 업데이트에만 latest 조회·사용을 허용한다.
- 버전은 로컬 도움말·공식 정보 또는 `mise ls-remote <tool>`로 확인하고 기존 도구의 호환성을 검토한다.
- 시스템 패키지가 필요하면 현재 OS의 패키지 매니저를 확인한다. apt 설치 자동화는 `DEBIAN_FRONTEND=noninteractive`와 `-y`를 사용한다.
- 설치를 수행한 경우 `mise install`, `mise ls`와 바이너리 실행으로 결과를 확인한다. 선언만 수정한 작업은 설치 미실행 여부와 관련 검사 결과를 보고한다.
