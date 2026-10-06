# 프롬프트와 검증 자산

`contexts/`는 공통 지침, 작업별 SKILL, 저장소 고유 reference와 실행 가능한 검증 자산의 원본입니다.
작업별 진입점과 참조 경로는 [INDEX.md](INDEX.md)에서 확인할 수 있습니다.

## 적용 방식

- `base.AGENTS.md`: 한국어 선호, 변경 범위, 권한·시크릿 경계, 검증과 커밋 기본값.
- `dotfiles/SKILL.md`: 이 저장소의 구조·검증 명령과 로컬 계약. 글로벌 등록에서 제외하고 루트 `AGENTS.md`·`CLAUDE.md`로 연결합니다.
- 그 밖의 `SKILL.md`: 해당 도메인의 사용 조건과 이 저장소가 실제로 강제하는 검증 계약. 일반 기술 지식은 현재 코드와 공식 문서를 기준으로 판단합니다.
- `references/`: SKILL 하나로 충분하지 않은 Repo-Specific 또는 정확한 Output Contract만 둡니다. 현재는 dotfiles 3개와 drawio-gen 8개만 유지합니다.
- `scripts/`, `tests/`, `evals/`, `examples/`: 실행 도구, 회귀 테스트, 평가·예제 자산. 프롬프트 문서를 줄여도 실행 검증 자산은 별도로 유지합니다.

런타임 에이전트에는 SKILL과 존재하는 reference/scripts/examples를 심볼릭 링크로 배포합니다. `tests/`와 `evals/`는 원본 저장소에서만 실행합니다.

## 유지보수 기준

모델이 이미 알고 있거나 코드·공식 문서에서 바로 확인할 수 있는 일반 기술 지식은 반복하지 않습니다.
저장소만 보고 알기 어려운 경로·출력 계약·보안/권한 경계·실제 실패 방지책·실행 가능한 검증을 우선합니다.

- 정적으로 판정할 수 있는 조건은 문서보다 테스트·린터로 강제합니다.
- reference는 독립적으로 읽어야 할 Repo-Specific 정보나 정확한 Output Contract가 있을 때만 분리합니다.
- 고정된 자가비판 절차, 설명 비율, 문체 템플릿 자체를 유지 목적으로 보존하지 않습니다.
- 규칙을 없애거나 이름을 바꾸면 이를 인용하는 문서·테스트·배포 호출부를 함께 확인합니다.
- 문서 길이 감소나 린트 통과만으로 성능 개선을 주장하지 않습니다. 필요한 경우 대표 작업에서 성공 여부와 도구 호출·질문·시간·비용을 비교합니다.

에셋은 심볼릭 링크로 배포하므로 기존 파일의 **내용 수정**에는 setup 재실행이 필요하지 않습니다. 새 스킬/에셋 추가·삭제처럼 링크 집합이 바뀌는 변경은 배포 연결과 bootstrap smoke를 확인합니다.

## 검증 명령

저장소 루트에서 실행합니다.

```bash
bash bin/linters/prompt-lint.sh
bash contexts/prompt-architect/tests/run.sh
```

SKILL의 description 또는 라우팅 표를 변경하면 색인을 재생성합니다.

```bash
just docs-index
```

전체 저장소 회귀까지 확인하려면:

```bash
just verify
```

`contexts/prompt-architect/evals/routing/run.sh --check-cases-only`는 라우팅 정답지의 정합성을 검사합니다.
실제 모델 측정인 `measure.sh`는 에이전트 세션 비용이 발생하므로 명시적인 실행 요청이 있을 때만 사용합니다.
