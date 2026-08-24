# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

AndroRingTrack is a SwiftUI iOS + watchOS companion app for the AndroSwitch masculine contraceptive ring. It tracks wear sessions (start/stop timing, history, stats) with HealthKit as the single source of truth for session data, and syncs settings between iPhone and Watch via WatchConnectivity.

## Build & run

This is an Xcode project (no SPM/CocoaPods package manifest, no CLI test runner configured). Use Xcode or `xcodebuild`:

```bash
# Build the iOS app
xcodebuild -project AndroRingTrack.xcodeproj -scheme "AndroRingTrack (iOS)" -configuration Debug build

# Build the Watch app
xcodebuild -project AndroRingTrack.xcodeproj -scheme "WatchAndroRingTrack" -configuration Debug build
```

There are no test targets in this project — do not assume `xcodebuild test` works.

- Swift version: 5.0
- Deployment targets: iOS 14.3, watchOS 7.4
- Bundle IDs: `com.astralym.AndroRingTrack` (iOS), `.watchkitapp` / `.watchkitapp.watchkitextension` (Watch)

## Architecture

### Code sharing model

The project is split into three targets that all pull from one shared layer:

- `Shared/` — models, stores, services, extensions, and shared views used by both `iOS/` and the Watch targets. This is where almost all business logic lives.
- `iOS/` — iOS-only views (`iOS/Views/`) and app entry point.
- `WatchAndroRingTrack Extension/` — watchOS-only views, complication, and notification controller.

Platform-specific code inside `Shared/` is guarded with `#if os(watchOS)` / `#if os(iOS)` (see `SettingsStore.swift`, `WatchConnectivity.swift`).

### Data flow

`Record` (`Shared/Models/Record.swift`) is the atomic unit: a wear session with an optional `start`/`end` date. `Day` (`Shared/Models/Day.swift`) is a derived, non-persisted grouping of a day's `Record`s used for duration/progress calculations — it is not stored anywhere itself.

`RecordStore` (`Shared/Stores/RecordStore.swift`) is a singleton `ObservableObject` (`RecordStore.shared`) that holds `@Published var records: [Record]` and `@Published var state: RingState` (`.worn` / `.off`). It is the single place session start/stop/edit/delete logic lives:
- `markAsWorn()` / `markAsRemoved()` toggle `state`, mutate `records`, and push the change to HealthKit.
- All mutations (`addRecord`, `editRecord`, `deleteRecord`, `markAsWorn`, `markAsRemoved`) go through `HealthKitService` — HealthKit is the actual persistence layer; `records` is a local cache refreshed via `refreshHealthData()`.
- Ending a session under 3 minutes deletes the HealthKit sample instead of storing it (treated as accidental toggle).
- Session start/end also schedules local notifications via `Notifications` (`scheduleNotifyEnd`, `scheduleReminderStart`).

`HealthKitService` (`Shared/Services/HealthKit.swift`) is a singleton wrapping `HKHealthStore`, scoped to a single `HKCategoryType`: `.contraceptive`. Every write path (`storeRecord`, `editRecord`, `removeRecord`) first queries for an existing/incomplete sample with a matching start date and deletes it before writing the new one — HealthKit samples are treated as immutable, so "edit" is always delete + recreate. `registerForSync` sets up an `HKObserverQuery` so external HealthKit changes (e.g. edits made in the Health app) get pulled back via `RecordStore.refreshHealthData()`.

`SettingsStore` (`Shared/Stores/SettingsStore.swift`) is a singleton `ObservableObject` for user preferences (`themeColor`, `sessionLength`, `notifications`), persisted to `UserDefaults`. Any setter triggers `WatchConnectivity.shared.sync()` to push the new value to the paired device.

### iPhone/Watch sync

`WatchConnectivity` (`Shared/Services/WatchConnectivity.swift`) is a singleton wrapping `WCSession`. It only syncs `SettingsStore`'s lightweight `appContext` dict (`themeColor`, `sessionLength`) via `updateApplicationContext` — it does not sync `Record`/session data (each side reads HealthKit directly for that). Incoming context updates are received via a Combine `PassthroughSubject` and applied in `SettingsStore.onReceiveContextUpdate` (watchOS only).

### Notifications

`Notifications` (`Shared/Services/Notifications.swift`) schedules local `UserNotifications` for session-end and reminder-to-start, driven by `SettingsStore.sessionLength` and `NotificationsSettings`. Rescheduled whenever a record affecting "today" changes (see the `editingCurrent` checks in `RecordStore`).

### Logging

Use `AppLogger` (`Shared/Services/AppLogger.swift`), a thin wrapper over `os.Logger`, for all logging — pass a `context:` string identifying the originating type (matches the existing pattern of `context: "RecordStore"`, etc.). Errors from `HealthKitServiceError` expose `.errorDescription` for logging/display.

### Localization

Strings live in `Shared/en.lproj/Localizable.strings` and `Shared/fr.lproj/Localizable.strings` (English/French).
