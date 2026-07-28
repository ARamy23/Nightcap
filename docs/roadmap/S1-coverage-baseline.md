# S1 — Coverage Baseline

Captured 2026-07-29, commit `25ee63a` + local signing override.
Toolchain: Xcode 27.0 via Xcode MCP (`windowtab3`). No `xcodebuild`.

## Test run

15 tests, **15 passed**, 0 failed, 0 skipped. Scheme `Nightcap`, test plan `Nightcap`.

## Per-file coverage, `Nightcap.app` target (52.83% overall, 486/920)

| File | Coverage | Classification |
|---|---|---|
| `Domain/WatchedApp.swift` | **100.00%** (13/13) | pure domain |
| `Domain/LaunchAtLoginStatus.swift` | **100.00%** (13/13) | pure domain |
| `AppFeature.swift` | **93.14%** (258/277) | domain logic (reducer) |
| `NightcapApp.swift` | 100.00% (25/25) | composition root |
| `SharedUI/WatchedAppsMenuSection.swift` | 82.35% (84/102) | UI |
| `SharedUI/MenuContentView.swift` | 58.54% (48/82) | UI |
| `SharedUI/MenuStatusSection.swift` | 57.14% (8/14) | UI |
| `SharedUI/MenuActionsSection.swift` | 28.95% (11/38) | UI |
| `SharedUI/MenuAppPicker.swift` | 0.00% (0/63) | UI |
| `SharedUI/AddRunningAppMenu.swift` | 0.00% (0/64) | UI |
| `Services/PowerAssertionClient.swift` | 31.48% (17/54) | live IOKit adapter |
| `Services/LaunchAtLoginClient.swift` | 30.00% (3/10) | live SMAppService adapter |
| `Services/AppQuitterClient.swift` | 18.18% (2/11) | live NSApp adapter |
| `Services/ReviewPromptClient.swift` | 14.29% (2/14) | live StoreKit adapter |
| `Services/AppLifecycleClient.swift` | 1.43% (2/140) | live NSWorkspace adapter |

## Domain-logic total

`WatchedApp` + `LaunchAtLoginStatus` + `AppFeature` = **284/303 = 93.7%**

**The S4 goal of 80% pure-domain coverage is already met, before any work.**
S4 therefore becomes: encode the gate so it cannot regress, not chase a number.

## S2 acceptance gate

The BDD rewrite must hold every number above. Specifically:
- 15 → at least 15 scenarios, all passing
- `WatchedApp` and `LaunchAtLoginStatus` stay at 100%
- `AppFeature` ≥ 93.14%

Any drop means the translation lost a case.

## Notes for later slices

- Uncovered code is concentrated in live adapters (`AppLifecycleClient` 1.43%) and
  SwiftUI menu views. Neither is domain logic; both are correctly excluded from the gate.
- `AppFeature.swift:1` imports AppKit but uses **no** AppKit symbol. S5's domain
  extraction starts by deleting that import — the reducer is already pure.
