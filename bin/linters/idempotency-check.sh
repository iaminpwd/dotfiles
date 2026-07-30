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
      # heredoc 시작 탐지 (<<EOF, <<EOL 등 << 뒤에 단어가 오는 패턴)
      if (!in_heredoc && $0 ~ /<<[A-Z_a-z]/) {
        idx = index($0, "<<")
        rest = substr($0, idx + 2)
        sub(/^[[:space:]]*/, "", rest)
        sub(/[^A-Z_a-z0-9].*/, "", rest)
        if (rest != "") { heredoc_end = rest; in_heredoc = 1 }
      } else if (in_heredoc && $0 == heredoc_end) {
        in_heredoc = 0
        next
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
