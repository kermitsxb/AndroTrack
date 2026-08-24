# AndroRingTrack Widget — Design Spec

Status: Approved
Date: 2026-08-24

## Context

The README lists "Widget" as an unimplemented feature suggestion. This spec
covers adding a WidgetKit extension so users can see wear status and today's
progress from the Home Screen / Lock Screen without opening the app.

## Goals

- Show current wear status (worn/off) and today's total worn duration at a
  glance.
- Support tapping the widget to toggle wear status directly, without opening
  the app, on devices that support it.
- Reuse the existing `Shared/` business logic (`RecordStore`,
  `HealthKitService`, `SettingsStore`) rather than duplicating it or building
  a separate sync mechanism — consistent with how the Watch target already
  works.

## Non-goals

- No new persistence layer or App Group / IPC data channel. HealthKit stays
  the single source of truth; the widget reads it directly, same as the
  Watch app does today.
- No calendar view, history browsing, or session editing from the widget.
- No support below iOS 15 (matches the project's existing deployment
  target) or below watchOS — this is an iOS-only Home Screen / Lock Screen
  widget, not a Watch complication addition (the Watch complication already
  exists separately).

## Architecture

### New target

`AndroRingTrackWidget` — a WidgetKit App Extension target, added alongside
`iOS/` and `WatchAndroRingTrack Extension/`. It links `Shared/` directly,
following the project's existing three-target-pulling-from-one-shared-layer
pattern (see CLAUDE.md "Code sharing model"). Widget-only UI (SwiftUI views,
the `Widget`/`WidgetBundle` entry point, the `TimelineProvider`, and the
`AppIntent`) lives inside the new target, not in `Shared/`.

### Data flow

The widget extension does not talk to the main app process. It uses its own
`HKHealthStore` instance (via the existing `HealthKitService` singleton,
scoped to the same `.contraceptive` `HKCategoryType`) to read the current
`RingState` and today's `Record`s, exactly as `RecordStore.refreshHealthData()`
does in the app and Watch targets. HealthKit authorization is requested by
the main app (existing onboarding flow); the widget extension assumes
authorization has already been granted and cannot itself trigger the
permission sheet.

### Families & content

| Family | Content |
|---|---|
| `.systemSmall` | Status icon (worn/off) + today's total worn duration |
| `.systemMedium` | Status icon + duration + progress bar toward the day's session-length goal (reusing the same goal logic as the app's stats view) |
| `.accessoryCircular` (Lock Screen, iOS 16+) | Compact status glyph |
| `.accessoryRectangular` (Lock Screen, iOS 16+) | Status + short duration text |

### Timeline provider

A `TimelineProvider` builds entries from `RecordStore`/`HealthKitService`
state:
- While the ring is worn, the entry's elapsed-time text uses
  `Text(timerInterval:)` so it updates live on-device without repeated
  timeline reloads.
- `RecordStore.markAsWorn()` and `RecordStore.markAsRemoved()` call
  `WidgetCenter.shared.reloadAllTimelines()` after their HealthKit write
  succeeds, so the widget reflects state changes made from the app or Watch
  immediately rather than waiting for the system's next scheduled refresh.
- A fallback reload policy (`.after(endDate)` or a periodic interval) covers
  cases where no explicit reload fires (e.g. HealthKit changed externally,
  picked up via the existing `HKObserverQuery` registered by
  `HealthKitService.registerForSync`).

### Interactivity (iOS 17+)

A `ToggleWearIntent: AppIntent` calls `RecordStore.shared.markAsWorn()` /
`markAsRemoved()` directly (running in the extension process), then reloads
the timeline. Small/Medium and Lock Screen widgets render a tap target bound
to this intent on iOS 17+.

On iOS 15–16 (which lack interactive widget support), the widget is
non-interactive: it deep-links into the app via a `Link`/URL rather than
performing the toggle in-place.

### Error / unauthorized state

If a HealthKit query fails or authorization hasn't been granted yet, the
timeline shows a neutral placeholder entry ("Open app to set up") instead of
a stale or misleading status. Failures are logged via `AppLogger` with
`context: "Widget"`.

## Testing

The project has no test target (per CLAUDE.md — do not assume `xcodebuild
test` works). Verification is manual: Xcode's Widget preview canvas for
layout across families/sizes, and on-device testing for the interactive
`AppIntent` (simulator support for widget intents is limited).

## Open questions / follow-ups (not blocking this spec)

- Exact goal/progress-bar visual treatment for `.systemMedium` should match
  whatever the main app's stats view currently uses — to be confirmed
  against `Shared/` stats code during implementation, not re-designed here.
