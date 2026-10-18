---
trigger: dotfiles 변경 근거 이력을 확인하거나 룰 출처를 기록할 때 참조.
---
# 선택적 변경 근거 기록

- 공통 작업 경계는 `contexts/base.AGENTS.md`를 따른다. 사용자가 지정하지 않은 범위의 발견은 별도로 보고한다.
- 특정 `contexts/` 룰에 근거한 변경의 기록이 필요할 때만 `bash bin/utils/record-provenance.sh <file_path> <rule_source> <purpose>`를 실행한다. `rule_source` 예: `dotfiles/010-core.md`; 직접 지시·단순 수정에는 강제하지 않는다.
- 이전 기록은 `.agent-state/edits.log`에서 확인한다. 반복되는 룰 관련 실패는 기존 기록과 해당 룰을 대조한다.
