#!/usr/bin/env bash
# idempotency-check.sh
# Check if shell scripts use append without state checking

set -euo pipefail

FILES=("$@")

if [ ${#FILES[@]} -eq 0 ]; then
  exit 0
fi

for FILE in "${FILES[@]}"; do
  [ -f "$FILE" ] || continue

  # awk를 이용해 파일의 각 라인을 읽고, >>나 tee -a 가 쓰인 라인 주변(위아래 3줄)에
  # 멱등성 가드(grep -q, if [, if test 등)가 있는지 검사한다.
  awk '
    BEGIN { window_size = 3; in_heredoc = 0 }
    {
      opened_heredoc = 0
      # heredoc 시작 탐지: <<EOF, <<EOL 뿐 아니라 대시 형식(탭 들여쓰기 허용)과
      # 구분자를 따옴표로 감싼 형식까지 받는다. 이들을 놓치면 히어독 본문을 코드로
      # 오인해 본문 안의 >> 를 멱등성 위반으로 오탐한다(실측 재현).
      #
      # 산술 좌시프트를 히어독으로 오인하지 않으려면 << 의 앞뒤를 둘 다 봐야 한다.
      #   - << 뒤: 구분자 사이의 공백을 허용하지 않는다  -> x=$((1 << b)) 를 배제
      #   - << 앞: 줄 시작이거나 공백일 것을 요구한다     -> x=$((1<<b))  를 배제
      # 예전에는 뒤쪽 조건만 있어서, 더 흔한 무공백형이 구분자 "b" 짜리 히어독 시작으로
      # 오인됐고 그 아래 파일 전체가 히어독 본문 취급으로 조용히 무검사 처리됐다(실측
      # 재현: 1<<b 아래의 >> 2건이 모두 무경고). 이 저장소에는 `<< EOF` 처럼 띄어 쓰는
      # 히어독이 한 건도 없어 뒤쪽 조건을 유지해도 잃는 것이 없다.
      if (!in_heredoc && match($0, /(^|[[:space:]])<<-?["'"'"']?[A-Z_a-z]/)) {
        # 매치 지점부터 잘라낸다. index($0, "<<") 로 첫 << 를 찾으면 같은 줄 앞쪽에 있는
        # 무관한 << (좌시프트, 여기스트링 등)를 구분자로 오독할 수 있다.
        rest = substr($0, RSTART)
        sub(/^[[:space:]]*<</, "", rest)
        # <<- 의 대시와 구분자를 감싼 따옴표를 벗겨낸 뒤 구분자 이름만 남긴다.
        heredoc_dash = (rest ~ /^-/)
        sub(/^-/, "", rest)
        sub(/^["'"'"']/, "", rest)
        sub(/[^A-Z_a-z0-9].*/, "", rest)
        if (rest != "") { heredoc_end = rest; in_heredoc = 1; opened_heredoc = 1 }
      } else if (in_heredoc) {
        # <<- 형식은 종료 구분자 앞의 탭 들여쓰기가 허용되므로 비교 전에 벗겨낸다.
        end_line = $0
        if (heredoc_dash) { sub(/^[\t]+/, "", end_line) }
        if (end_line == heredoc_end) {
          in_heredoc = 0
          next
        }
      }
      # 건너뛰는 것은 히어독 "본문"뿐이다. 시작 줄 자체는 검사 대상으로 남긴다 —
      # `cat >> ~/.zshrc <<'"'"'EOF'"'"'` 처럼 append 와 히어독 시작이 한 줄에 있는 형태는
      # 이 린터가 잡으라고 존재하는 가장 전형적인 비멱등 패턴인데, 예전에는 그 줄이
      # in_heredoc 표시 직후 여기서 걸러져 append 후보로 등록조차 되지 못했다(실측:
      # `echo ... >> ~/.zshrc` 는 경고, `cat >> ~/.zshrc <<'"'"'EOF'"'"'` 는 무경고).
      if (in_heredoc && !opened_heredoc) next
      if ($0 ~ />>|tee -a/) { append_lines[NR] = 1 }
      if ($0 ~ /grep -q|if \[|if test|idempotency:bypass/) { guard_lines[NR] = 1 }
    }
    END {
      for (i in append_lines) {
        guarded = 0
        for (j = i - window_size; j <= i + window_size; j++) {
          if (guard_lines[j]) { guarded = 1; break }
        }
        if (!guarded) {
          print "⚠️ [WARNING] Idempotency check: \047" FILENAME "\047 at line " i " uses append (>> or tee -a) but lacks a nearby state checking logic (e.g., grep -q or if [ ... ]). Consider adding idempotency guards." > "/dev/stderr"
        }
      }
    }
  ' "$FILE"
done

exit 0
