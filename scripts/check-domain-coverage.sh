#!/bin/bash
# Fails if pure-domain coverage regresses below the threshold.
#
# Domain = the files that hold logic independent of AppKit/IOKit/SwiftUI.
# Live adapters (NSWorkspace, IOKit, SMAppService, StoreKit bridges) and SwiftUI
# views are deliberately excluded: covering them means UI/integration tests, not
# characterization.
#
# Usage: scripts/check-domain-coverage.sh <path-to-.xcresult> [threshold]
set -euo pipefail

XCRESULT="${1:?usage: $0 <path-to-.xcresult> [threshold]}"
THRESHOLD="${2:-80}"

DOMAIN_FILES=(
  "Nightcap/Domain/WatchedApp.swift"
  "Nightcap/Domain/LaunchAtLoginStatus.swift"
  "Nightcap/AppFeature.swift"
)

report=$(xcrun xccov view --report --files-for-target Nightcap.app "$XCRESULT")

covered=0
total=0
echo "Domain coverage:"
for file in "${DOMAIN_FILES[@]}"; do
  # xccov prints e.g. "93.14% (258/277)" — take the last (n/m) on the line.
  line=$(grep -F "/$file " <<<"$report" || true)
  if [[ -z "$line" ]]; then
    echo "  MISSING $file — not in coverage report" >&2
    exit 1
  fi
  # xccov pads columns with trailing spaces, so match the last (n/m) anywhere.
  fraction=$(grep -oE '\([0-9]+/[0-9]+\)' <<<"$line" | tail -1 | tr -d '()')
  c=${fraction%/*}
  t=${fraction#*/}
  covered=$((covered + c))
  total=$((total + t))
  filepct=$(awk -v c="$c" -v t="$t" 'BEGIN{printf "%.2f", c*100/t}')
  printf '  %-40s %6s%% (%s/%s)\n' "$(basename "$file")" "$filepct" "$c" "$t"
done

if (( total == 0 )); then
  echo "No domain lines found — coverage not enabled on the test plan?" >&2
  exit 1
fi

pct=$(awk -v c="$covered" -v t="$total" 'BEGIN{printf "%.2f", c*100/t}')
echo "  ----"
printf '  %-40s %s%% (%d/%d)\n' TOTAL "$pct" "$covered" "$total"

if awk "BEGIN{exit !($pct < $THRESHOLD)}"; then
  echo "FAIL: domain coverage $pct% is below the $THRESHOLD% threshold" >&2
  exit 1
fi

echo "PASS: domain coverage $pct% meets the $THRESHOLD% threshold"
