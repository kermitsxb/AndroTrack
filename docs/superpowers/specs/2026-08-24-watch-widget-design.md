# ThermoTrack Watch Widget — Design Spec

Status: Approved
Date: 2026-08-24

## Context

The iOS app now has a WidgetKit-based widget (Home Screen + Lock Screen,
see `docs/superpowers/specs/2026-08-24-widget-design.md`). The watchOS app
still relies on the legacy ClockKit complications API
(`WatchThermoTrack Extension/ComplicationController.swift` and
`Complications.swift`). Apple recommends WidgetKit for watch face
complications since watchOS 9, and unifying on WidgetKit lets the watch
gain a Smart Stack widget (watchOS 10+) using the same code that already
drives the complications, with no separate UI to build or maintain.

## Goals

- Replace the ClockKit complications with WidgetKit complications, covering
  the same visual intent as today (circular gauge, corner gauge, plus a new
  inline text style) across `.accessoryCircular`, `.accessoryCorner`,
  `.accessoryRectangular`, `.accessoryInline`.
- Reuse the same widget code across iOS and watchOS wherever the UI is
  shared (`.accessoryCircular`/`.accessoryRectangular` already exist for
  iOS's Lock Screen widget) rather than maintaining two implementations.
- Make the watch widget's daily goal correct for existing users immediately
  on upgrade, by fixing the App Group mirroring bug found in code review
  (`SettingsStore.sessionLength` mirroring never fires from `init()`, and
  was iOS-only).
- Keep the watch's own timelines fresh after a wear-state toggle on the
  watch itself (`RecordStore`'s `WidgetCenter.reloadAllTimelines()` calls
  become cross-platform instead of iOS-only, so the watch now reloads its
  own widget/complication timelines too — `WidgetCenter.reloadAllTimelines()`
  is process/device-local, so this does not make a toggle on one device
  refresh the other device's timeline; cross-device propagation still
  depends on HealthKit's own sync plus each side's periodic timeline
  refresh policy).

## Non-goals

- No tap-to-toggle interaction on the watch complication/widget (unlike the
  iOS widget's `ToggleWearIntent`). Not all complication families support
  it uniformly, and it wasn't requested.
- No support for watchOS below 9.0 — this raises the project's
  `WATCHOS_DEPLOYMENT_TARGET` from 8.0 to 9.0, dropping Apple Watch Series 3.
  Accepted trade-off (2017 hardware, watchOS 9+ covers the active install
  base).
- No new persistence or IPC layer. HealthKit stays the source of truth; the
  watch widget extension reads it directly via its own HealthKit
  entitlement, exactly like the iOS widget and the watch app already do.
- Keeping ClockKit alongside WidgetKit was considered and rejected — see
  Approaches below.

## Approaches considered

1. **Replace ClockKit entirely with WidgetKit (chosen).** One extension
   target, one set of SwiftUI views, shared with the iOS widget where the
   family overlaps. Matches Apple's current guidance and removes
   duplicate complication logic going forward.
2. **Add WidgetKit alongside existing ClockKit.** Would preserve watchOS 8
   support but means maintaining two complication implementations
   (`CLKComplicationTemplate` construction in `Complications.swift` and a
   parallel SwiftUI view) for the same visual result. Rejected: doubles
   maintenance for a device (Series 3) that's very old hardware.

## Architecture

A new WidgetKit extension target, `ThermoTrackWatchWidget`, embedded in
the watch app, replacing `ComplicationController`/`Complications`/the
`Complication.complicationset` asset catalog entry entirely. One
`WidgetBundle` with a single `Widget` (`WatchWearStatusWidget`) supporting
all four accessory families — watchOS doesn't distinguish "complication"
vs. "Smart Stack widget" configuration the way iOS distinguishes Home
Screen vs. Lock Screen; the same `StaticConfiguration` serves both
surfaces.

## Components

New target `ThermoTrackWatchWidget`:
- `WatchWearStatusWidgetBundle.swift` — `@main WidgetBundle`.
- `WatchWearStatusWidget.swift` — the `Widget` conformance, supporting
  `[.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline]`.
- `WatchWearStatusAccessoryView.swift` — new view. Reuses the circular and
  rectangular cases as already written in `WearStatusAccessoryView`
  (iOS widget target), and adds:
  - `.accessoryCorner`: gauge + icon, equivalent to the old
    `Complications.makeGraphicCorner`.
  - `.accessoryInline`: single line of text (e.g. today's duration vs.
    goal, or "En cours" while worn).
- Reused by file reference (added to this target alongside
  `ThermoTrackWidget`, not duplicated): `WearStatusProvider.swift`,
  `WearStatusEntry.swift`, `Views/DurationFormatting.swift`.
- `ThermoTrackWatchWidget.entitlements` — HealthKit entitlement +
  App Group `group.com.astralym.AndroThermoTrack` (same pattern as
  `ThermoTrackWidget.entitlements`).
- `Info.plist` with `NSExtensionPointIdentifier` =
  `com.apple.widgetkit-extension`, matching the iOS widget's Info.plist
  structure.

Removed: `WatchThermoTrack Extension/ComplicationController.swift`,
`WatchThermoTrack Extension/Views/Elements/Complications.swift`,
`WatchThermoTrack Extension/Assets.xcassets/Complication.complicationset`,
and their `project.pbxproj` references.

Cross-cutting fixes required for the watch widget to work correctly
(overlaps with the bug found in code review of the iOS widget branch):
- `Shared/Stores/SettingsStore.swift`: the `sessionLength` App Group
  mirror moves from `#if os(iOS)` to unconditional (iOS + watchOS), and
  `init()` explicitly mirrors the loaded value instead of relying on
  `didSet` (which Swift does not fire for assignments inside `init`).
- `Shared/Stores/RecordStore.swift`: the `WidgetCenter.reloadAllTimelines()`
  calls (currently `#if os(iOS)`-only, ~3 call sites) become unconditional
  so a toggle on either device refreshes the watch's complications/widget
  timeline too.
- `WatchThermoTrack Extension/WatchThermoTrack Extension.entitlements`:
  add the `group.com.astralym.AndroThermoTrack` App Group, needed for
  `SettingsStore` running in the watch app process to write into the
  shared suite.
- `project.pbxproj`: `WATCHOS_DEPLOYMENT_TARGET` 8.0 → 9.0 (all 4
  occurrences).

## Data flow

Same pattern as the iOS widget: `WearStatusProvider.getTimeline` queries
`HealthKitService.shared` directly (the widget extension has its own
HealthKit entitlement and runs in its own process), computes `worn`/`off`
state and today's `Day.duration`, and reads `goalInHours` from the App
Group suite — now populated from both the iPhone and the Watch after the
`SettingsStore` fix above.

## Edge cases

- **HealthKit not yet authorized in the widget extension's process**:
  falls back to the existing `unauthorizedEntry()` (neutral state, no
  crash) — unchanged from the iOS widget's handling.
- **Refresh cadence**: same `.after(reloadDate)` policy (15 min while worn,
  1h otherwise). No toggle interaction on the watch widget, so no need for
  a tighter budget than the iOS widget uses.
- **App Group suite not yet populated** (fresh install, or racing the
  `SettingsStore` fix rollout): falls back to the existing default of 15,
  same as iOS.
- **Apple Watch Series 3 / watchOS < 9**: no longer supported, per the
  deployment target change above.

## Testing

No test target exists in this project (see `CLAUDE.md`). Verification is
by build:

```bash
xcodebuild -project ThermoTrack.xcodeproj -scheme "WatchThermoTrack" -configuration Debug build
```

plus building the new `ThermoTrackWatchWidget` target once it's added
to the scheme, and manual verification in the watchOS simulator (adding
the complication to a watch face, and checking the Smart Stack) — no
automated UI testing exists in this project to extend.
