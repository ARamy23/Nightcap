#!/bin/bash
# Fails if pure-domain coverage regresses below the threshold.
#
# Domain = the files holding logic independent of AppKit/IOKit/SwiftUI. Live
# adapters (NSWorkspace, IOKit, SMAppService, StoreKit, NWPathMonitor) and
# SwiftUI views are excluded on purpose: covering those means integration or
# snapshot tests, not characterisation.
#
# Runs the domain package's tests through SwiftPM, so it needs no Xcode, no
# simulator and no scheme.
#
# Usage: scripts/check-domain-coverage.sh [threshold]
set -euo pipefail

THRESHOLD="${1:-80}"
PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Packages/NightcapDomain"

export DOMAIN_FILES="WatchedApp.swift LaunchAtLoginStatus.swift AppFeature.swift MacState.swift CompanionFeature.swift MacStateRecordCoding.swift"
export THRESHOLD

cd "$PACKAGE_DIR"
swift test --enable-code-coverage >/dev/null 2>&1
REPORT="$(swift test --enable-code-coverage --show-codecov-path 2>/dev/null)"

if [[ ! -f "$REPORT" ]]; then
  echo "No coverage report at $REPORT" >&2
  exit 1
fi

python3 - "$REPORT" <<'PY'
import json, os, sys

wanted = set(os.environ["DOMAIN_FILES"].split())
threshold = float(os.environ["THRESHOLD"])
data = json.load(open(sys.argv[1]))

covered = total = 0
seen = set()
print("Domain coverage:")
for f in data["data"][0]["files"]:
    name = f["filename"].split("/")[-1]
    if name not in wanted:
        continue
    seen.add(name)
    s = f["summary"]["lines"]
    covered += s["covered"]
    total += s["count"]
    print(f"  {name:<34}{s['percent']:6.2f}%  ({s['covered']}/{s['count']})")

missing = wanted - seen
if missing:
    print(f"  MISSING from coverage report: {', '.join(sorted(missing))}", file=sys.stderr)
    sys.exit(1)

if total == 0:
    print("  No domain lines found", file=sys.stderr)
    sys.exit(1)

pct = 100.0 * covered / total
print("  " + "-" * 48)
print(f"  {'TOTAL':<34}{pct:6.2f}%  ({covered}/{total})")

if pct < threshold:
    print(f"FAIL: domain coverage {pct:.2f}% is below the {threshold:.0f}% threshold", file=sys.stderr)
    sys.exit(1)

print(f"PASS: domain coverage {pct:.2f}% meets the {threshold:.0f}% threshold")
PY
