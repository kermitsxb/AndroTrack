# ThermoTrack Shortcuts & Siri Integration — Design Spec

Status: Approved (design), pending spec review
Date: 2026-09-25

## Context

The README roadmap lists "Shortcuts app integration" and "Siri integration"
as the remaining user-facing suggestions. The only App Intent in the codebase
today is `AndroRingTrackWidget/ToggleWearIntent.swift` (iOS 17+), compiled
into the widget extension only and used by the widget's toggle button. It is
not exposed to the Shortcuts app or to Siri (no app-target membership, no
`AppShortcutsProvider`).

That intent deliberately bypasses `RecordStore` (in the widget process
`RecordStore.shared` holds preview data) and reimplements the two session
rules directly on top of `HealthKitService`. It also deliberately skips the
local notifications (end-of-session, reminder-to-start) that app-triggered
toggles schedule, because those depend on `RecordStore.shared.current` and
`SettingsStore.shared`, neither of which is usable outside the app process.

## Goals

- Expose four actions in the Shortcuts app, all iOS 17+:
  - **Start session** (`StartWearIntent`)
  - **Stop session** (`StopWearIntent`)
  - **Toggle wear state** (`ToggleWearIntent`, the existing intent)
  - **Get wear status** (`GetWearStatusIntent`), returning a value usable in
    other shortcuts
- Make them invocable by voice through Siri with English and French App
  Shortcut phrases, without opening the app.
- Apply exactly the same session rules as the app, from every entry point
  (Shortcuts, Siri, widget button):
  - starting while a session is open is a no-op;
  - ending a session shorter than 3 minutes deletes the HealthKit sample
    instead of storing it (accidental toggle).
- Keep local notifications correct from every entry point, **including the
  widget button** (removes the current documented simplification):
  - start → cancel reminder-to-start, schedule notify-end at the estimated
    end of today's goal (if `notifyEnd` is enabled);
  - stop → cancel notify-end, schedule the repeating reminder-to-start (if
    `reminderStart` is enabled).

## Non-goals

- watchOS. The watch targets watchOS 8; App Intents require watchOS 9+.
- Intent parameters (custom start time, editing past records).
- Spotlight/Focus filter/interactive-snippet customisation beyond what
  `AppShortcutsProvider` gives for free.
- Changing `RecordStore`'s own start/stop implementation. It keeps working as
  today; external HealthKit changes made by intents are already pulled back
  through its `HKObserverQuery` (`refreshHealthData()`).

## Architecture

### 1. Shared settings via the App Group

`SettingsStore` already mirrors `sessionLength` into
`UserDefaults(suiteName: "group.com.astralym.AndroRingTrack")`
(`mirrorSessionLengthToAppGroup()`, called from `didSet` and from `init()`).

Extend this so `notifications` (`NotificationsSettings`: `reminderStart`,
`notifyEnd`, `reminderTime`) is mirrored too, encoded the same way
`SettingsStore` stores it in `UserDefaults.standard` (`trySet` / `typed`),
from both its `didSet` and `init()`. Mirroring is iOS-only in effect but
harmless on watchOS.

Add a small reader, `AppGroupSettings` (`Shared/Stores/AppGroupSettings.swift`),
with static accessors `sessionLength: Int` (default 15, same as
`SettingsStore`) and `notifications: NotificationsSettings` (default
`NotificationsSettings()`), reading only from the App Group suite. It has no
dependency on `SettingsStore`, WatchConnectivity or SwiftUI, so it can be
compiled into the widget extension. The widget's existing
`currentGoalInHours()` may switch to it (optional clean-up, same key).

Until the app has been launched once after the update, `notifications` is
absent from the App Group; `AppGroupSettings` then returns defaults (both
notification kinds disabled), so intents schedule nothing. This is the
accepted degradation.

### 2. Notifications decoupled from app singletons

Add parameterised variants to `Notifications` (`Shared/Services/Notifications.swift`):

- `scheduleNotifyEnd(today: Day, sessionLength: Int, settings: NotificationsSettings)`
- `scheduleReminderStart(settings: NotificationsSettings)`

`scheduleReminderStartNotification()` gains a `reminderTime: Date`
parameter instead of reading `SettingsStore.shared`.

The existing no-argument `scheduleNotifyEnd()` / `scheduleReminderStart()`
become thin wrappers passing `RecordStore.shared.current`,
`SettingsStore.shared.sessionLength` and `SettingsStore.shared.notifications`,
so every existing call site behaves exactly as before.

All four iOS/watch targets (app, widget, watch extension, watch widget)
already compile `Notifications.swift`, `RecordStore.swift` and
`SettingsStore.swift`, so no target-membership change is needed here. The
point of the parameterised variants is not compilation but correctness: in
the widget process `RecordStore.shared` holds preview data and
`SettingsStore.shared` reads the widget's own (empty) `UserDefaults.standard`,
so intents must pass real values instead of relying on those singletons.

### 3. Pure session logic (unit-tested)

`Shared/Models/WearSessionLogic.swift`, no HealthKit/UIKit/SwiftUI imports:

```swift
enum WearAction: Equatable {
    case start                 // no open session → create one now
    case store(Record)         // close open session, keep it
    case discard(start: Date)  // close open session, < 3 min → delete sample
    case none                  // nothing to do
}

enum WearSessionLogic {
    static let minimumSessionMinutes: Double = 3
    static func startAction(records: [Record]) -> WearAction   // .start or .none
    static func stopAction(records: [Record], now: Date) -> WearAction // .store/.discard/.none
    static func toggleAction(records: [Record], now: Date) -> WearAction
    static func openRecord(in records: [Record]) -> Record?
}
```

`stopAction` returns a closed copy of the open record (end = `now`) so the
logic is deterministic in tests. The threshold check uses the same `< 3`
minutes rule as `RecordStore.markAsRemoved()`.

A `WearStatus` value type in the same file holds the read-side result:
`isWorn`, `sessionStart: Date?`, `todayMinutes: Int`, `goalHours: Int`,
`progressPercent: Int`, built by `WearStatus.make(records:goalHours:now:)`
using `Day.today(from:now:)`.

Both are added to the `AndroRingTrackTests` target's compile sources.

### 4. `WearSessionService` (HealthKit side)

`Shared/Services/WearSessionService.swift`, iOS 17+ where needed, compiled
into the app and the widget extension. Stateless, `async`:

- `status() async throws -> WearStatus`
- `start() async throws -> WearOutcome`
- `stop() async throws -> WearOutcome`
- `toggle() async throws -> WearOutcome`

`WearOutcome` is `.started(Date)`, `.alreadyStarted(Date)`, `.stopped(Record)`,
`.discarded`, `.notRunning`.

Each mutating call:

1. checks HealthKit authorisation; if not `.sharingAuthorized`, throws
   `WearSessionError.healthKitNotAuthorized`;
2. fetches recent records (`fetchRecords(since:)`, two days back, like the
   widget provider);
3. asks `WearSessionLogic` which action to take;
4. performs it through `HealthKitService` (`storeRecord` / `removeRecord`),
   bridged to `async` with checked continuations (moved from the current
   `ToggleWearIntent`);
5. reschedules notifications with `Notifications`' parameterised variants,
   computing today's `Day` from the fetched records updated with the action,
   and settings from `AppGroupSettings`;
6. calls `WidgetCenter.shared.reloadAllTimelines()`.

HealthKit errors are logged with `AppLogger` (`context: "WearSessionService"`)
and rethrown.

### 5. Intents

`Shared/Intents/` (iOS 17+, `@available(iOS 17.0, *)`), compiled into the
iOS app and the widget extension:

| Intent | Result | Dialog (EN, FR localised) |
|---|---|---|
| `StartWearIntent` | — | "Session started at 08:12." / "Already worn since 08:12." |
| `StopWearIntent` | — | "Session ended: 7 h 05." / "Session cancelled (under 3 min)." / "No session in progress." |
| `ToggleWearIntent` | — | same dialogs as start/stop |
| `GetWearStatusIntent` | `Int` (minutes worn today) | "Worn since 08:12 · 6 h 40 today (44 % of the 15 h goal)." / "Not worn · 6 h 40 today (44 % of the 15 h goal)." |

All have `openAppWhenRun = false`. `ToggleWearIntent` moves from
`AndroRingTrackWidget/` to `Shared/Intents/` and delegates to
`WearSessionService.toggle()`; the widget button keeps using it unchanged.

`WearSessionError` conforms to `CustomLocalizedStringResourceConvertible` so
Shortcuts/Siri show "Open ThermoTrack to allow Health access." when
unauthorised.

### 6. `AppShortcutsProvider`

`iOS/Intents/ThermoTrackShortcuts.swift`, app target only. One
`AppShortcut` per intent, each with a system image and phrases containing
`\(.applicationName)`, e.g.:

- Start: "Start a session in \(.applicationName)", "I put on my ring in \(.applicationName)"
- Stop: "Stop my session in \(.applicationName)", "I took off my ring in \(.applicationName)"
- Toggle: "Toggle my ring in \(.applicationName)"
- Status: "How long have I worn it today in \(.applicationName)", "\(.applicationName) status"

French phrases go in `AppShortcuts.xcstrings` (or `fr.lproj/AppShortcuts.strings`,
whichever the Xcode version's App Shortcuts localisation supports for this
project); intent titles and dialogs go in the existing `Localizable.strings`.

### Target membership summary

| File | iOS app | Widget ext. | Tests |
|---|---|---|---|
| `Shared/Stores/AppGroupSettings.swift` | ✓ | ✓ | |
| `Shared/Services/Notifications.swift` | ✓ (already) | ✓ (already) | |
| `Shared/Models/WearSessionLogic.swift` | ✓ | ✓ | ✓ |
| `Shared/Services/WearSessionService.swift` | ✓ | ✓ | |
| `Shared/Intents/*.swift` | ✓ | ✓ | |
| `iOS/Intents/ThermoTrackShortcuts.swift` | ✓ | | |

Watch targets keep their current membership. `ToggleWearIntent.swift` moves
from `AndroRingTrackWidget/` to `Shared/Intents/` and gains app-target
membership.

## Error handling

- HealthKit not authorised → localised error, no write.
- HealthKit read/write failure → logged, rethrown; Shortcuts shows the error.
- Notification permission not granted → `Notifications.scheduleNotification`
  already bails out silently with an info log; unchanged.
- Settings not yet mirrored → defaults, no notification scheduled.

## Testing

- Unit (`AndroRingTrackTests`): `WearSessionLogic` start/stop/toggle
  decisions (no records, open record, closed records only, open record under
  and over 3 minutes, boundary at exactly 3 minutes) and `WearStatus.make`
  (worn/off, progress rounding, previous-day finished session excluded).
- Build: iOS app scheme and widget extension compile; watch scheme still
  compiles.
- Manual: in the Shortcuts app, run each action (authorised and not), verify
  HealthKit samples, notification scheduling (pending requests), widget
  refresh, and Siri phrases in EN and FR.

## Documentation

- README: tick "Shortcuts app integration" and "Siri integration".
- CLAUDE.md: mention `WearSessionService` as the entry point for session
  changes outside the app process, and `AppGroupSettings` for settings reads.
