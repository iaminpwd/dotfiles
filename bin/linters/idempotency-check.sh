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
      # heredoc 시작 탐지: <<EOF, <<EOL 뿐 아니라 대시 형식(탭 들여쓰기 허용)과
      # 구분자를 따옴표로 감싼 형식까지 받는다. 이들을 놓치면 히어독 본문을 코드로
      # 오인해 본문 안의 >> 를 멱등성 위반으로 오탐한다(실측 재현).
      #
      # << 와 구분자 사이의 공백은 일부러 허용하지 않는다. 허용하면 산술 좌시프트
      # (x=$((1 << b)))가 구분자 "b" 짜리 히어독 시작으로 오인되어, 그 아래 파일 전체가
      # 히어독 본문 취급으로 조용히 무검사 처리된다(실측 재현). 이 저장소에는 `<< EOF`
      # 처럼 띄어 쓰는 히어독이 한 건도 없어 얻는 것 없이 무검증 통과만 생긴다.
      if (!in_heredoc && $0 ~ /<<-?["'"'"']?[A-Z_a-z]/) {
        idx = index($0, "<<")
        rest = substr($0, idx + 2)
        # <<- 의 대시와 구분자를 감싼 따옴표를 벗겨낸 뒤 구분자 이름만 남긴다.
        sub(/^-/, "", rest)
        sub(/^[[:space:]]*/, "", rest)
        sub(/^["'"'"']/, "", rest)
        sub(/[^A-Z_a-z0-9].*/, "", rest)
        if (rest != "") { heredoc_end = rest; in_heredoc = 1; heredoc_dash = ($0 ~ /<<-/) }
      } else if (in_heredoc) {
        # <<- 형식은 종료 구분자 앞의 탭 들여쓰기가 허용되므로 비교 전에 벗겨낸다.
        end_line = $0
        if (heredoc_dash) { sub(/^[\t]+/, "", end_line) }
        if (end_line == heredoc_end) {
          in_heredoc = 0
          next
        }
      }
      if (in_heredoc) next
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
