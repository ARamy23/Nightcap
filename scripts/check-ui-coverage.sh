#!/bin/bash
# Fails if UI / presentation coverage regresses below the thresholds.
#
# Two numbers are reported, because the goal is not just "covered" but "covered
# in the right way":
#
#   1. TOTAL coverage of the SwiftUI layer — which state each view renders, and
#      which action each control sends.
#   2. SNAPSHOT coverage — the share of those same lines reached when *only* the
#      snapshot suites run. Layout regressions are invisible to a string
#      assertion, so a high total built entirely from unit tests would be a false
#      comfort.
#
# Both NightcapUI (the Mac menu bar) and NightcapCompanionUI (the iPhone and
# Watch screen) are measured, since both are presentation.
#
# One file is excluded: MenuAppPicker.swift. NSOpenPanel.runModal() and
# NSAlert.runModal() block on a real window server, so nothing in it can run
# under a test. Every decision it used to make now lives in MenuAppPickerLogic,
# which is measured here. This is the rule the domain gate already applies to the
# IOKit, NSWorkspace, SMAppService and StoreKit adapters.
#
# Nothing else is excluded. In particular, view bodies nested inside a SwiftUI
# `Menu` are not evaluated until the menu opens, so their regions stay uncovered
# and are still counted against us — a real, if structural, gap rather than one
# defined away.
#
# Runs through SwiftPM, so it needs no Xcode, no simulator and no scheme.
#
# Usage: scripts/check-ui-coverage.sh [total-threshold] [snapshot-threshold]
set -euo pipefail

TOTAL_THRESHOLD="${1:-80}"
SNAPSHOT_THRESHOLD="${2:-60}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PACKAGES=(NightcapUI NightcapCompanionUI)

# Swift Testing suite names carrying the snapshot assertions. Kept explicit
# rather than pattern-matched so that adding a suite is a deliberate act.
# One regex rather than a list: --filter is a regex, and it must match in *both*
# packages, since a filter matching nothing makes that package report zero.
# It matches suite *type* names — --filter does not see the display names.
SNAPSHOT_FILTER="(MenuSnapshotTests|MenuContentSnapshotTests|CompanionSnapshotTests|CompanionScreenTests)"

report_path() {
  # $1 = package dir, rest = swift test args
  local dir="$1"; shift
  (cd "$dir" && swift test --enable-code-coverage "$@" >/dev/null 2>&1 || true)
  (cd "$dir" && swift test --enable-code-coverage "$@" --show-codecov-path 2>/dev/null)
}

ALL_REPORTS=()
SNAPSHOT_REPORTS=()

for pkg in "${PACKAGES[@]}"; do
  dir="$ROOT/Packages/$pkg"

  full="$(report_path "$dir")"
  [[ -f "$full" ]] || { echo "No coverage report for $pkg" >&2; exit 1; }
  # Every run writes to the same path per package, so each report is copied
  # aside before the next run overwrites it.
  full_copy="$(mktemp -t nightcap-cov)"
  cp "$full" "$full_copy"
  ALL_REPORTS+=("$full_copy")

  # Re-run with only the snapshot suites so the profile reflects them alone.
  snap="$(report_path "$dir" --filter "$SNAPSHOT_FILTER")"
  [[ -f "$snap" ]] || { echo "No snapshot-only coverage report for $pkg" >&2; exit 1; }
  snap_copy="$(mktemp -t nightcap-snap-cov)"
  cp "$snap" "$snap_copy"
  SNAPSHOT_REPORTS+=("$snap_copy")
done

export TOTAL_THRESHOLD SNAPSHOT_THRESHOLD
export ALL_REPORTS_JOINED="${ALL_REPORTS[*]}"
export SNAPSHOT_REPORTS_JOINED="${SNAPSHOT_REPORTS[*]}"

python3 <<'PY'
import json, os, sys

EXCLUDED = {"MenuAppPicker.swift"}
SOURCE_MARKERS = ("/NightcapUI/Sources/", "/NightcapCompanionUI/Sources/")

def collect(paths):
    """file basename -> (covered, count), summed across reports."""
    out = {}
    for path in paths:
        with open(path) as handle:
            data = json.load(handle)
        for f in data["data"][0]["files"]:
            name = f["filename"]
            if not any(m in name for m in SOURCE_MARKERS):
                continue
            base = name.split("/")[-1]
            if base in EXCLUDED:
                continue
            s = f["summary"]["lines"]
            prev = out.get(base, (0, 0))
            # Same file can appear in both packages' reports only if shared;
            # take the better-covered reading rather than double-counting.
            out[base] = max(prev, (s["covered"], s["count"]))
    return out

total_threshold = float(os.environ["TOTAL_THRESHOLD"])
snapshot_threshold = float(os.environ["SNAPSHOT_THRESHOLD"])

full = collect(os.environ["ALL_REPORTS_JOINED"].split())
snap = collect(os.environ["SNAPSHOT_REPORTS_JOINED"].split())

if not full:
    print("No UI source files found in the coverage reports", file=sys.stderr)
    sys.exit(1)

print("UI / presentation coverage:")
print(f"  {'file':<34}{'total':>9}{'snapshot':>11}")
covered = count = 0
snap_covered = 0
for base in sorted(full):
    c, n = full[base]
    sc, _ = snap.get(base, (0, 0))
    covered += c
    count += n
    snap_covered += sc
    pct = 100.0 * c / n if n else 0.0
    spct = 100.0 * sc / n if n else 0.0
    print(f"  {base:<34}{pct:8.2f}%{spct:10.2f}%")

for base in sorted(EXCLUDED):
    print(f"  {base:<34}{'excluded':>9}  (window-server only)")

if count == 0:
    print("  No measurable UI lines", file=sys.stderr)
    sys.exit(1)

total_pct = 100.0 * covered / count
snap_pct = 100.0 * snap_covered / count
print("  " + "-" * 53)
print(f"  {'TOTAL':<34}{total_pct:8.2f}%{snap_pct:10.2f}%   ({covered}/{count})")

failed = False
if total_pct < total_threshold:
    print(f"FAIL: UI coverage {total_pct:.2f}% is below the {total_threshold:.0f}% threshold", file=sys.stderr)
    failed = True
else:
    print(f"PASS: UI coverage {total_pct:.2f}% meets the {total_threshold:.0f}% threshold")

if snap_pct < snapshot_threshold:
    print(f"FAIL: snapshot coverage {snap_pct:.2f}% is below the {snapshot_threshold:.0f}% threshold", file=sys.stderr)
    failed = True
else:
    print(f"PASS: snapshot coverage {snap_pct:.2f}% meets the {snapshot_threshold:.0f}% threshold")

sys.exit(1 if failed else 0)
PY
