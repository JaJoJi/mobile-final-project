#!/usr/bin/env bash
# Fail if total line coverage in an lcov file is below a floor.
# Mobile coverage gate for Jenkins (#274, #282). Originally mirrored the
# GitHub Actions mobile-ci.yml step, removed when Jenkins became the only CI.
#
# Usage: lcov-floor.sh <lcov.info> <min-percent>
set -euo pipefail
FILE="${1:?lcov file}"
MIN="${2:?min percent}"

LH=$(awk -F: '/^LH:/{s+=$2} END{print s+0}' "$FILE")
LF=$(awk -F: '/^LF:/{s+=$2} END{print s+0}' "$FILE")
if [ "$LF" -eq 0 ]; then
  echo "No instrumented lines in $FILE — refusing to pass an empty report" >&2
  exit 1
fi
PCT=$(awk "BEGIN{printf \"%.2f\", 100*${LH}/${LF}}")
echo "Line coverage: ${PCT}% (${LH}/${LF}), floor ${MIN}%"
awk "BEGIN{exit !(${PCT} >= ${MIN})}"
