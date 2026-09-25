# Shortcuts & Siri Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose Start / Stop / Toggle / Get-status wear-session actions in the Shortcuts app and to Siri (EN + FR), applying the app's session rules and notification scheduling from every entry point, widget button included.

**Architecture:** A pure, unit-tested `WearSessionLogic` decides what a start/stop/toggle does given the HealthKit records. A stateless `WearSessionService` (async) fetches records from HealthKit, applies the decision, reschedules notifications from settings mirrored into the App Group (`AppGroupSettings`), and reloads widgets. Four iOS 17+ App Intents call the service; an `AppShortcutsProvider` in the app target registers Siri phrases.

**Tech Stack:** Swift 5 (Xcode 26), SwiftUI app with iOS 15 deployment target, App Intents (iOS 17+, `@available`), HealthKit, UserNotifications, WidgetKit, XCTest. Project file edits are scripted with the `xcodeproj` Ruby gem (1.27.0, installed), as in earlier plans.

**Spec:** `docs/superpowers/specs/2026-09-25-shortcuts-siri-design.md`

## Global Constraints

- iOS deployment target stays `15.0`; every App Intents type is `@available(iOS 17.0, *)` (error conformance may be `iOS 16.0`).
- watchOS is out of scope: no new file joins a watch target, except `AppGroupSettings.swift` (needed because `SettingsStore.swift` is compiled into the watch targets).
- App Group suite name: `group.com.astralym.AndroRingTrack`. Keys: `sessionLength` (Int, default 15), `notifications` (JSON-encoded `NotificationsSettings`, default `NotificationsSettings()`).
- Minimum stored session: strictly under 3 minutes → the HealthKit sample is deleted instead of stored (same as `RecordStore.markAsRemoved()`); exactly 3 minutes is stored.
- Starting while a session is open never creates a second sample.
- Records fetch window for intents: 7 days back.
- Logging goes through `AppLogger` with `context: "<TypeName>"`.
- User-facing strings live in `Shared/en.lproj/Localizable.strings` and `Shared/fr.lproj/Localizable.strings`; Siri phrase translations in `iOS/fr.lproj/AppShortcuts.strings`.
- Target names (exact): `AndroRingTrack (iOS)`, `AndroRingTrackWidget`, `WatchAndroRingTrack Extension`, `AndroRingTrackWatchWidget`, `AndroRingTrackTests`.
- Do not add Claude session URLs or Co-Authored-By lines to commits.

## Build & test commands (used by every task)

```bash
# iOS app (also builds the embedded AndroRingTrackWidget extension)
xcodebuild -project AndroRingTrack.xcodeproj -scheme "AndroRingTrack (iOS)" -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build -quiet

# Watch app
xcodebuild -project AndroRingTrack.xcodeproj -scheme "WatchAndroRingTrack" -configuration Debug -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build -quiet

# Unit tests
xcodebuild -project AndroRingTrack.xcodeproj -scheme AndroRingTrackTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test -quiet
```

## Review Focus

1. **Siri "start" while a session is already running** → no second sample, dialog "Already worn since HH:MM". Pinned by `testStartActionDoesNothingWhenSessionIsOpen` and `testOutcomeForNoneWithOpenSessionIsAlreadyStarted` (Task 1).
2. **Stop at the 3-minute boundary** → 2:59 discarded, 3:00 stored. Pinned by `testStopActionDiscardsSessionUnderThreeMinutes` / `testStopActionStoresSessionOfExactlyThreeMinutes` (Task 1).
3. **Long ongoing session (started 3+ days ago)** → stop must still find it. Pinned by `testStopActionFindsSessionStartedDaysAgo` (Task 1) and the 7-day fetch window (Task 4).
4. **App updated but not reopened (settings never mirrored)** → intents work, schedule no notification, don't crash. Covered by `AppGroupSettings` defaults (Task 2) and manual check in Task 6.
5. **Status just after midnight with a session started yesterday** → today's minutes are clipped at midnight, not the full session. Pinned by `testStatusClipsOngoingSessionFromYesterdayAtMidnight` (Task 1).

---

### Task 1: Pure session logic (`WearSessionLogic`, `WearStatus`, `WearOutcome`)

**Files:**
- Create: `Shared/Models/WearSessionLogic.swift`
- Create: `Tests/WearSessionLogicTests.swift`
- Modify: `AndroRingTrack.xcodeproj/project.pbxproj` (scripted)

**Interfaces:**
- Consumes: `Record` (`class`, `id: UUID`, `start: Date?`, `end: Date?`, `init(id:start:end:)`), `Day.today(from:now:)`, `Day.duration` (hours, `Double`).
- Produces:
  - `enum WearAction: Equatable { case start; case store(Record); case discard(start: Date); case none }`
  - `enum WearOutcome: Equatable { case started(Date); case alreadyStarted(Date); case stopped(Record); case discarded; case notRunning }`
  - `enum WearSessionLogic` with `static let minimumSessionMinutes: Double`, `static func openRecord(in: [Record]) -> Record?`, `static func startAction(records: [Record], now: Date) -> WearAction`, `static func stopAction(records: [Record], now: Date) -> WearAction`, `static func toggleAction(records: [Record], now: Date) -> WearAction`, `static func records(_: [Record], applying: WearAction, now: Date) -> [Record]`, `static func outcome(for: WearAction, records: [Record], now: Date) -> WearOutcome`
  - `struct WearStatus: Equatable { isWorn: Bool; sessionStart: Date?; todayMinutes: Int; goalHours: Int; progressPercent: Int }` with `static func make(records: [Record], goalHours: Int, now: Date = Date()) -> WearStatus`

- [ ] **Step 1: Write the failing tests**

Create `Tests/WearSessionLogicTests.swift`:

```swift
//
//  WearSessionLogicTests.swift
//  AndroRingTrackTests
//

import XCTest

final class WearSessionLogicTests: XCTestCase {
    private let calendar = Calendar.current
    private var todayStart: Date { calendar.startOfDay(for: Date()) }

    /// Builds a date relative to the start of today: `at(-1, 20, 30)` is yesterday at 20:30.
    private func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(byAdding: .minute, value: dayOffset * 1440 + hour * 60 + minute, to: todayStart)!
    }

    // MARK: - openRecord(in:)

    func testOpenRecordIsNilWhenAllRecordsAreClosed() {
        let closed = Record(start: at(0, 1), end: at(0, 5))
        XCTAssertNil(WearSessionLogic.openRecord(in: [closed]))
    }

    func testOpenRecordPicksMostRecentWhenSeveralAreOpen() {
        let older = Record(start: at(-1, 8), end: nil)
        let newer = Record(start: at(0, 8), end: nil)
        XCTAssertTrue(WearSessionLogic.openRecord(in: [newer, older]) === newer)
        XCTAssertTrue(WearSessionLogic.openRecord(in: [older, newer]) === newer)
    }

    // MARK: - startAction

    func testStartActionStartsWhenNoSessionIsOpen() {
        let closed = Record(start: at(0, 1), end: at(0, 5))
        XCTAssertEqual(WearSessionLogic.startAction(records: [closed], now: at(0, 6)), .start)
    }

    func testStartActionDoesNothingWhenSessionIsOpen() {
        let open = Record(start: at(0, 1), end: nil)
        XCTAssertEqual(WearSessionLogic.startAction(records: [open], now: at(0, 6)), WearAction.none)
    }

    // MARK: - stopAction

    func testStopActionDoesNothingWithoutOpenSession() {
        let closed = Record(start: at(0, 1), end: at(0, 5))
        XCTAssertEqual(WearSessionLogic.stopAction(records: [closed], now: at(0, 6)), WearAction.none)
    }

    func testStopActionStoresSessionOfExactlyThreeMinutes() {
        let start = at(0, 8)
        let open = Record(start: start, end: nil)
        let now = start.addingTimeInterval(3 * 60)

        guard case .store(let closed) = WearSessionLogic.stopAction(records: [open], now: now) else {
            return XCTFail("expected .store")
        }
        XCTAssertEqual(closed.id, open.id)
        XCTAssertEqual(closed.start, start)
        XCTAssertEqual(closed.end, now)
    }

    func testStopActionDiscardsSessionUnderThreeMinutes() {
        let start = at(0, 8)
        let open = Record(start: start, end: nil)
        let now = start.addingTimeInterval(3 * 60 - 1)

        XCTAssertEqual(WearSessionLogic.stopAction(records: [open], now: now), .discard(start: start))
    }

    func testStopActionDoesNotMutateTheOpenRecord() {
        let open = Record(start: at(0, 8), end: nil)
        _ = WearSessionLogic.stopAction(records: [open], now: at(0, 12))
        XCTAssertNil(open.end)
    }

    func testStopActionFindsSessionStartedDaysAgo() {
        let open = Record(start: at(-3, 8), end: nil)
        guard case .store(let closed) = WearSessionLogic.stopAction(records: [open], now: at(0, 12)) else {
            return XCTFail("expected .store")
        }
        XCTAssertEqual(closed.start, at(-3, 8))
    }

    // MARK: - toggleAction

    func testToggleStartsWhenNothingIsOpen() {
        XCTAssertEqual(WearSessionLogic.toggleAction(records: [], now: at(0, 6)), .start)
    }

    func testToggleStopsOpenSession() {
        let open = Record(start: at(0, 1), end: nil)
        guard case .store = WearSessionLogic.toggleAction(records: [open], now: at(0, 6)) else {
            return XCTFail("expected .store")
        }
    }

    // MARK: - records(_:applying:now:)

    func testApplyingStartAppendsOpenRecordAtNow() {
        let closed = Record(start: at(0, 1), end: at(0, 5))
        let result = WearSessionLogic.records([closed], applying: .start, now: at(0, 6))

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.last?.start, at(0, 6))
        XCTAssertNil(result.last?.end)
    }

    func testApplyingStoreReplacesOpenRecordById() {
        let other = Record(start: at(0, 1), end: at(0, 2))
        let open = Record(start: at(0, 3), end: nil)
        let closed = Record(id: open.id, start: at(0, 3), end: at(0, 9))

        let result = WearSessionLogic.records([other, open], applying: .store(closed), now: at(0, 9))

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0 === closed })
        XCTAssertFalse(result.contains { $0 === open })
    }

    func testApplyingDiscardRemovesRecordWithThatStart() {
        let other = Record(start: at(0, 1), end: at(0, 2))
        let open = Record(start: at(0, 3), end: nil)

        let result = WearSessionLogic.records([other, open], applying: .discard(start: at(0, 3)), now: at(0, 3, 1))

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first === other)
    }

    // MARK: - outcome(for:records:now:)

    func testOutcomeForStartIsStartedAtNow() {
        XCTAssertEqual(WearSessionLogic.outcome(for: .start, records: [], now: at(0, 6)), .started(at(0, 6)))
    }

    func testOutcomeForNoneWithOpenSessionIsAlreadyStarted() {
        let open = Record(start: at(0, 1), end: nil)
        XCTAssertEqual(WearSessionLogic.outcome(for: .none, records: [open], now: at(0, 6)), .alreadyStarted(at(0, 1)))
    }

    func testOutcomeForNoneWithoutOpenSessionIsNotRunning() {
        XCTAssertEqual(WearSessionLogic.outcome(for: .none, records: [], now: at(0, 6)), .notRunning)
    }

    func testOutcomeForDiscardIsDiscarded() {
        XCTAssertEqual(WearSessionLogic.outcome(for: .discard(start: at(0, 1)), records: [], now: at(0, 6)), .discarded)
    }

    // MARK: - WearStatus.make

    func testStatusWhenOffSumsTodayAndRoundsProgress() {
        // 6h30 worn today, goal 15h → 390 / 900 = 43.3 %
        let closed = Record(start: at(0, 1), end: at(0, 7, 30))

        let status = WearStatus.make(records: [closed], goalHours: 15, now: at(0, 12))

        XCTAssertFalse(status.isWorn)
        XCTAssertNil(status.sessionStart)
        XCTAssertEqual(status.todayMinutes, 390)
        XCTAssertEqual(status.goalHours, 15)
        XCTAssertEqual(status.progressPercent, 43)
    }

    func testStatusExcludesFinishedSessionStartedYesterday() {
        let spillover = Record(start: at(-1, 20), end: at(0, 2))

        let status = WearStatus.make(records: [spillover], goalHours: 15, now: at(0, 12))

        XCTAssertEqual(status.todayMinutes, 0)
        XCTAssertEqual(status.progressPercent, 0)
    }

    func testStatusWhenWornReportsSessionStart() {
        let start = Date().addingTimeInterval(-10 * 60)
        let open = Record(start: start, end: nil)

        let status = WearStatus.make(records: [open], goalHours: 15)

        XCTAssertTrue(status.isWorn)
        XCTAssertEqual(status.sessionStart, start)
    }

    func testStatusClipsOngoingSessionFromYesterdayAtMidnight() {
        let open = Record(start: at(-1, 20), end: nil)

        let status = WearStatus.make(records: [open], goalHours: 15)

        let minutesSinceMidnight = Int((Date().timeIntervalSince(todayStart) / 60).rounded())
        XCTAssertTrue(status.isWorn)
        XCTAssertEqual(status.todayMinutes, minutesSinceMidnight, accuracy: 1)
    }

    func testStatusWithZeroGoalHasZeroProgress() {
        let closed = Record(start: at(0, 1), end: at(0, 2))
        XCTAssertEqual(WearStatus.make(records: [closed], goalHours: 0, now: at(0, 12)).progressPercent, 0)
    }
}
```

- [ ] **Step 2: Add the files to the Xcode project**

Create an empty `Shared/Models/WearSessionLogic.swift` (so the reference resolves), then run from the repo root:

```bash
touch Shared/Models/WearSessionLogic.swift
ruby <<'RUBY'
require 'xcodeproj'
project = Xcodeproj::Project.open('AndroRingTrack.xcodeproj')

def group_for(project, dir)
  dir.split('/').reduce(project.main_group) do |g, name|
    g.children.find { |c| c.isa == 'PBXGroup' && c.path == name } || g.new_group(name, name)
  end
end

def add_file(project, path, target_names)
  group = group_for(project, File.dirname(path))
  ref = group.files.find { |f| f.path == File.basename(path) } || group.new_reference(File.basename(path))
  target_names.each do |name|
    target = project.targets.find { |t| t.name == name } or abort("no target #{name}")
    target.add_file_references([ref]) unless target.source_build_phase.files_references.include?(ref)
  end
end

add_file(project, 'Shared/Models/WearSessionLogic.swift', ['AndroRingTrack (iOS)', 'AndroRingTrackWidget', 'AndroRingTrackTests'])
add_file(project, 'Tests/WearSessionLogicTests.swift', ['AndroRingTrackTests'])
project.save
RUBY
plutil -lint AndroRingTrack.xcodeproj/project.pbxproj
```

Expected: `AndroRingTrack.xcodeproj/project.pbxproj: OK`

- [ ] **Step 3: Run tests to verify they fail**

Run the unit test command. Expected: build FAILS with `cannot find 'WearSessionLogic' in scope` (and `WearStatus`, `WearAction`, `WearOutcome`).

- [ ] **Step 4: Write the implementation**

Write `Shared/Models/WearSessionLogic.swift`:

```swift
//
//  WearSessionLogic.swift
//  ThermoTrack
//

import Foundation

/// What a start/stop/toggle request should do to HealthKit, decided from the current records.
enum WearAction: Equatable {
    /// No session is open: create one starting now.
    case start
    /// Close the open session and keep it (the associated record is the closed copy).
    case store(Record)
    /// Close the open session and delete its sample: it lasted under `minimumSessionMinutes`.
    case discard(start: Date)
    /// Nothing to do.
    case none
}

/// What happened, as reported back to the user by Shortcuts/Siri.
enum WearOutcome: Equatable {
    case started(Date)
    case alreadyStarted(Date)
    case stopped(Record)
    case discarded
    case notRunning
}

/// Session rules shared by the App Intents and the widget button. Mirrors `RecordStore`'s
/// `markAsWorn()` / `markAsRemoved()` but works on a plain record list, so it runs in any
/// process and is unit-testable.
enum WearSessionLogic {
    /// Sessions strictly shorter than this are treated as accidental toggles.
    static let minimumSessionMinutes: Double = 3

    /// The most recent session without an end date, if any.
    static func openRecord(in records: [Record]) -> Record? {
        records
            .filter { $0.start != nil && $0.end == nil }
            .max { $0.start! < $1.start! }
    }

    static func startAction(records: [Record], now: Date) -> WearAction {
        openRecord(in: records) == nil ? .start : .none
    }

    /// Returns a closed copy of the open record; the record passed in is never mutated.
    static func stopAction(records: [Record], now: Date) -> WearAction {
        guard let open = openRecord(in: records), let start = open.start else { return .none }

        if now.timeIntervalSince(start) / 60 < minimumSessionMinutes {
            return .discard(start: start)
        }
        return .store(Record(id: open.id, start: start, end: now))
    }

    static func toggleAction(records: [Record], now: Date) -> WearAction {
        openRecord(in: records) == nil ? .start : stopAction(records: records, now: now)
    }

    /// The record list as it will be once `action` has been written to HealthKit.
    static func records(_ records: [Record], applying action: WearAction, now: Date) -> [Record] {
        switch action {
        case .start:
            return records + [Record(start: now)]
        case .store(let closed):
            return records.map { $0.id == closed.id ? closed : $0 }
        case .discard(let start):
            return records.filter { $0.start != start }
        case .none:
            return records
        }
    }

    static func outcome(for action: WearAction, records: [Record], now: Date) -> WearOutcome {
        switch action {
        case .start:
            return .started(now)
        case .store(let closed):
            return .stopped(closed)
        case .discard:
            return .discarded
        case .none:
            if let start = openRecord(in: records)?.start {
                return .alreadyStarted(start)
            }
            return .notRunning
        }
    }
}

/// Read-side snapshot returned by the "Get wear status" intent.
struct WearStatus: Equatable {
    let isWorn: Bool
    let sessionStart: Date?
    let todayMinutes: Int
    let goalHours: Int
    let progressPercent: Int

    static func make(records: [Record], goalHours: Int, now: Date = Date()) -> WearStatus {
        let open = WearSessionLogic.openRecord(in: records)
        let today = Day.today(from: records, now: now)
        let minutes = Int((today.duration * 60).rounded())
        let percent = goalHours > 0
            ? Int((Double(minutes) / Double(goalHours * 60) * 100).rounded())
            : 0

        return WearStatus(
            isWorn: open != nil,
            sessionStart: open?.start,
            todayMinutes: minutes,
            goalHours: goalHours,
            progressPercent: percent
        )
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run the unit test command. Expected: `** TEST SUCCEEDED **`, all `WearSessionLogicTests` and existing `DayTests` pass.

- [ ] **Step 6: Build the iOS app**

Run the iOS build command. Expected: `** BUILD SUCCEEDED **` (the file compiles in the app and widget targets).

- [ ] **Step 7: Commit**

```bash
git add Shared/Models/WearSessionLogic.swift Tests/WearSessionLogicTests.swift AndroRingTrack.xcodeproj/project.pbxproj
git commit -m "feat: add pure wear session logic for intents"
```

---

### Task 2: Mirror notification settings into the App Group (`AppGroupSettings`)

**Files:**
- Create: `Shared/Stores/AppGroupSettings.swift`
- Modify: `Shared/Stores/SettingsStore.swift` (`notifications` `didSet`, `init()`, `mirrorSessionLengthToAppGroup()`)
- Modify: `AndroRingTrackWidget/WearStatusProvider.swift` (`currentGoalInHours()`)
- Modify: `AndroRingTrack.xcodeproj/project.pbxproj` (scripted)

**Interfaces:**
- Consumes: `NotificationsSettings` (`Codable`, defaults: `reminderStart = false`, `notifyEnd = false`), `UserDefaults.trySet(_:forKey:)` / `typed(forKey:)` from `Shared/Extensions/UserDefaults+Extension.swift`.
- Produces: `enum AppGroupSettings` with `static var sessionLength: Int`, `static var notifications: NotificationsSettings`, `static func mirror(sessionLength: Int)`, `static func mirror(notifications: NotificationsSettings)`.

No unit test: `UserDefaults+Extension.swift` pulls SwiftUI/`Color` helpers into the dependency graph, which the host-less test target deliberately avoids. Verified by building all targets and the manual check in Task 6.

- [ ] **Step 1: Create `Shared/Stores/AppGroupSettings.swift`**

```swift
//
//  AppGroupSettings.swift
//  ThermoTrack
//

import Foundation

/// Settings shared with processes that can't use `SettingsStore` (the widget extension,
/// App Intents run by Shortcuts/Siri). `SettingsStore` writes them; everyone else reads
/// them from here. Until the app has written a value, readers get the same defaults as
/// `SettingsStore`.
enum AppGroupSettings {
    static let suiteName = "group.com.astralym.AndroRingTrack"

    private static let sessionLengthKey = "sessionLength"
    private static let notificationsKey = "notifications"

    private static var suite: UserDefaults? { UserDefaults(suiteName: suiteName) }

    static var sessionLength: Int {
        (suite?.object(forKey: sessionLengthKey) as? Int) ?? 15
    }

    static var notifications: NotificationsSettings {
        guard let suite = suite, let stored: NotificationsSettings = suite.typed(forKey: notificationsKey) else {
            return NotificationsSettings()
        }
        return stored
    }

    static func mirror(sessionLength: Int) {
        suite?.set(sessionLength, forKey: sessionLengthKey)
    }

    static func mirror(notifications: NotificationsSettings) {
        do {
            try suite?.trySet(notifications, forKey: notificationsKey)
        } catch {
            AppLogger.warning(context: "AppGroupSettings", "Unable to mirror notifications settings")
        }
    }
}
```

- [ ] **Step 2: Add it to every target that compiles `SettingsStore.swift`**

```bash
ruby <<'RUBY'
require 'xcodeproj'
project = Xcodeproj::Project.open('AndroRingTrack.xcodeproj')

def group_for(project, dir)
  dir.split('/').reduce(project.main_group) do |g, name|
    g.children.find { |c| c.isa == 'PBXGroup' && c.path == name } || g.new_group(name, name)
  end
end

def add_file(project, path, target_names)
  group = group_for(project, File.dirname(path))
  ref = group.files.find { |f| f.path == File.basename(path) } || group.new_reference(File.basename(path))
  target_names.each do |name|
    target = project.targets.find { |t| t.name == name } or abort("no target #{name}")
    target.add_file_references([ref]) unless target.source_build_phase.files_references.include?(ref)
  end
end

add_file(project, 'Shared/Stores/AppGroupSettings.swift',
         ['AndroRingTrack (iOS)', 'AndroRingTrackWidget', 'WatchAndroRingTrack Extension', 'AndroRingTrackWatchWidget'])
project.save
RUBY
plutil -lint AndroRingTrack.xcodeproj/project.pbxproj
```

Expected: `OK`.

- [ ] **Step 3: Mirror from `SettingsStore`**

In `Shared/Stores/SettingsStore.swift`, replace the `notifications` property:

```swift
    @Published var notifications: NotificationsSettings {
        didSet {
            do {
                try UserDefaults.standard.trySet(notifications, forKey: "notifications")
            } catch {
                AppLogger.warning(context: "SettingsStore", "Unable to save notifications settings")
            }
            AppGroupSettings.mirror(notifications: notifications)
        }
    }
```

In `init()`, right after the existing `mirrorSessionLengthToAppGroup()` line, add:

```swift
        // `didSet` doesn't fire for the value assigned in `init()` either.
        AppGroupSettings.mirror(notifications: notifications)
```

Replace the body of `mirrorSessionLengthToAppGroup()` (keep its doc comment):

```swift
    private func mirrorSessionLengthToAppGroup() {
        AppGroupSettings.mirror(sessionLength: sessionLength)
        WidgetCenter.shared.reloadAllTimelines()
    }
```

- [ ] **Step 4: Read the goal through `AppGroupSettings` in the widget**

In `AndroRingTrackWidget/WearStatusProvider.swift`, replace `currentGoalInHours()`:

```swift
    private func currentGoalInHours() -> Int {
        AppGroupSettings.sessionLength
    }
```

- [ ] **Step 5: Build iOS and watch, run tests**

Run the iOS build, watch build and unit test commands. Expected: both `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Shared/Stores/AppGroupSettings.swift Shared/Stores/SettingsStore.swift AndroRingTrackWidget/WearStatusProvider.swift AndroRingTrack.xcodeproj/project.pbxproj
git commit -m "feat: mirror notification settings into the App Group"
```

---

### Task 3: Parameterised notification scheduling

**Files:**
- Modify: `Shared/Services/Notifications.swift` (the two `extension Notifications` blocks)

**Interfaces:**
- Consumes: `Day.estimatedEnd(forDuration:)`, `NotificationsSettings`, `RecordStore.shared.current`, `SettingsStore.shared`.
- Produces:
  - `static func scheduleNotifyEnd(today: Day, sessionLength: Int, settings: NotificationsSettings)`
  - `static func scheduleReminderStart(settings: NotificationsSettings)`
  - `static func scheduleReminderStartNotification(reminderTime: Date = SettingsStore.shared.notifications.reminderTime)`
  - Existing `scheduleNotifyEnd()` / `scheduleReminderStart()` / `scheduleReminderStartNotification()` call sites keep compiling and behaving identically.

This is a behaviour-preserving refactor of code with no test seam (UserNotifications); verification is the build plus the manual checks in Task 6.

- [ ] **Step 1: Replace the notify-end extension**

Replace the second `extension Notifications { ... }` block (the one containing `scheduleNotifyEndNotification`) with:

```swift
extension Notifications {
    static func scheduleNotifyEndNotification(at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("NOTIFY_END_NOTIF.TITLE", comment: "")
        content.subtitle = NSLocalizedString("NOTIFY_END_NOTIF.SUBTITLE", comment: "")
        content.sound = UNNotificationSound.default
        
        let dateComponents = Calendar.current.dateComponents([.day, .hour, .minute], from: date)
        
        Notifications.scheduleNotification(content, at: dateComponents, forId: NotificationType.notifyEnd.rawValue)
    }
    
    static func cancelNotifyEndNotification() {
        Notifications.cancelNotificationWith(id: NotificationType.notifyEnd.rawValue)
    }
    
    static func scheduleNotifyEnd() {
        scheduleNotifyEnd(
            today: RecordStore.shared.current,
            sessionLength: SettingsStore.shared.sessionLength,
            settings: SettingsStore.shared.notifications
        )
    }

    /// Variant usable outside the app process, where `RecordStore`/`SettingsStore` hold no real data.
    static func scheduleNotifyEnd(today: Day, sessionLength: Int, settings: NotificationsSettings) {
        if settings.notifyEnd {
            guard let estimatedEnd = today.estimatedEnd(forDuration: sessionLength) else {
                AppLogger.error(context: "Notifications", "Can't determine estimatedEnd")
                return
            }
            
            Notifications.cancelReminderStartNotification()
            Notifications.cancelNotifyEndNotification()
            Notifications.scheduleNotifyEndNotification(at: estimatedEnd)
        }
    }
}
```

- [ ] **Step 2: Replace the reminder-start extension**

Replace the last `extension Notifications { ... }` block with:

```swift
extension Notifications {
    static func scheduleReminderStartNotification(reminderTime: Date = SettingsStore.shared.notifications.reminderTime) {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("REMINDED_START_NOTIF.TITLE", comment: "")
        content.subtitle = NSLocalizedString("REMINDED_START_NOTIF.SUBTITLE", comment: "")
        content.sound = UNNotificationSound.default
        
        let dateComponents = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        
        Notifications.scheduleNotification(content, at: dateComponents, repeats: true, forId: NotificationType.reminderStart.rawValue)
    }
    
    static func cancelReminderStartNotification() {
        Notifications.cancelNotificationWith(id: NotificationType.reminderStart.rawValue)
    }
    
    static func scheduleReminderStart() {
        scheduleReminderStart(settings: SettingsStore.shared.notifications)
    }

    /// Variant usable outside the app process, where `SettingsStore` holds no real data.
    static func scheduleReminderStart(settings: NotificationsSettings) {
        if settings.reminderStart {
            Notifications.cancelNotifyEndNotification()
            Notifications.cancelReminderStartNotification()
            Notifications.scheduleReminderStartNotification(reminderTime: settings.reminderTime)
        }
    }
}
```

Note: the old error log used `context: "RecordStore"`; it now uses `"Notifications"`, the originating type.

- [ ] **Step 3: Build iOS and watch, run tests**

Run the iOS build, watch build and unit test commands. Expected: `** BUILD SUCCEEDED **` twice, `** TEST SUCCEEDED **`. `iOS/Views/SettingsView.swift` still calls `scheduleReminderStartNotification()` with no argument and must compile unchanged.

- [ ] **Step 4: Commit**

```bash
git add Shared/Services/Notifications.swift
git commit -m "refactor: let notifications be scheduled from explicit settings"
```

---

### Task 4: `WearSessionService`

**Files:**
- Create: `Shared/Services/WearSessionService.swift`
- Modify: `AndroRingTrack.xcodeproj/project.pbxproj` (scripted)

**Interfaces:**
- Consumes: Task 1 (`WearSessionLogic`, `WearAction`, `WearOutcome`, `WearStatus`), Task 2 (`AppGroupSettings.sessionLength`, `.notifications`), Task 3 (`Notifications.scheduleNotifyEnd(today:sessionLength:settings:)`, `Notifications.scheduleReminderStart(settings:)`), `HealthKitService.shared` (`healthKitAuthorizationStatus`, `fetchRecords(since:completion:)`, `storeRecord(record:completion:)`, `removeRecord(at:completion:)`), `HealthKitServiceError.errorDescription`.
- Produces:
  - `enum WearSessionError: Error { case healthKitNotAuthorized; case healthKit(HealthKitServiceError) }`
  - `final class WearSessionService` with `static let shared`, `func status() async throws -> WearStatus`, `func start() async throws -> WearOutcome`, `func stop() async throws -> WearOutcome`, `func toggle() async throws -> WearOutcome`.

HealthKit-bound, no unit test seam; the decisions it makes are covered by Task 1's tests. Verified by build and Task 6 manual checks.

- [ ] **Step 1: Create `Shared/Services/WearSessionService.swift`**

```swift
//
//  WearSessionService.swift
//  ThermoTrack
//

import Foundation
import HealthKit
import WidgetKit

enum WearSessionError: Error {
    case healthKitNotAuthorized
    case healthKit(HealthKitServiceError)
}

/// Starts/stops wear sessions straight against HealthKit, for callers that run outside the
/// app's UI (App Intents from Shortcuts/Siri, the widget button). `RecordStore.shared` can't be
/// used there: in an extension process it only holds preview data. Changes made here reach a
/// running app through `RecordStore`'s HealthKit observer query.
final class WearSessionService {
    static let shared = WearSessionService()

    /// An ongoing session is stored with end == start, so the fetch window must reach back to the
    /// start of the longest plausible ongoing session, not just today.
    private static let fetchWindowDays = 7

    private let healthKit = HealthKitService.shared

    private init() {}

    func status() async throws -> WearStatus {
        try ensureAuthorized()
        let records = try await fetchRecentRecords()
        return WearStatus.make(records: records, goalHours: AppGroupSettings.sessionLength)
    }

    func start() async throws -> WearOutcome {
        try await perform(WearSessionLogic.startAction)
    }

    func stop() async throws -> WearOutcome {
        try await perform(WearSessionLogic.stopAction)
    }

    func toggle() async throws -> WearOutcome {
        try await perform(WearSessionLogic.toggleAction)
    }

    private func perform(_ decide: ([Record], Date) -> WearAction) async throws -> WearOutcome {
        try ensureAuthorized()

        let now = Date()
        let records = try await fetchRecentRecords()
        let action = decide(records, now)

        switch action {
        case .start:
            try await store(Record(start: now))
        case .store(let closed):
            try await store(closed)
        case .discard(let start):
            try await remove(at: start)
        case .none:
            break
        }

        if action != .none {
            let updated = WearSessionLogic.records(records, applying: action, now: now)
            rescheduleNotifications(after: action, records: updated, now: now)
            WidgetCenter.shared.reloadAllTimelines()
        }

        return WearSessionLogic.outcome(for: action, records: records, now: now)
    }

    /// Same calls as `RecordStore.markAsWorn()` / `markAsRemoved()`, fed with App Group settings.
    private func rescheduleNotifications(after action: WearAction, records: [Record], now: Date) {
        let settings = AppGroupSettings.notifications

        switch action {
        case .start:
            Notifications.scheduleNotifyEnd(
                today: Day.today(from: records, now: now),
                sessionLength: AppGroupSettings.sessionLength,
                settings: settings
            )
        case .store, .discard:
            Notifications.scheduleReminderStart(settings: settings)
        case .none:
            break
        }
    }

    private func ensureAuthorized() throws {
        guard healthKit.healthKitAuthorizationStatus == .sharingAuthorized else {
            throw WearSessionError.healthKitNotAuthorized
        }
    }

    private func fetchRecentRecords() async throws -> [Record] {
        let since = Calendar.current.date(byAdding: .day, value: -Self.fetchWindowDays, to: Date())
            ?? Date().addingTimeInterval(-Double(Self.fetchWindowDays) * 24 * 60 * 60)

        return try await withCheckedThrowingContinuation { continuation in
            healthKit.fetchRecords(since: since) { records, error in
                if let error = error {
                    AppLogger.error(context: "WearSessionService", "Failed to fetch records: \(error.errorDescription ?? "unknown")")
                    continuation.resume(throwing: WearSessionError.healthKit(error))
                } else {
                    continuation.resume(returning: records ?? [])
                }
            }
        }
    }

    private func store(_ record: Record) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthKit.storeRecord(record: record) { error in
                if let error = error {
                    AppLogger.error(context: "WearSessionService", "Failed to store record: \(error.errorDescription ?? "unknown")")
                    continuation.resume(throwing: WearSessionError.healthKit(error))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func remove(at start: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthKit.removeRecord(at: start) { error in
                if let error = error {
                    AppLogger.error(context: "WearSessionService", "Failed to remove record: \(error.errorDescription ?? "unknown")")
                    continuation.resume(throwing: WearSessionError.healthKit(error))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
```

- [ ] **Step 2: Add it to the iOS app and widget targets**

```bash
ruby <<'RUBY'
require 'xcodeproj'
project = Xcodeproj::Project.open('AndroRingTrack.xcodeproj')

def group_for(project, dir)
  dir.split('/').reduce(project.main_group) do |g, name|
    g.children.find { |c| c.isa == 'PBXGroup' && c.path == name } || g.new_group(name, name)
  end
end

def add_file(project, path, target_names)
  group = group_for(project, File.dirname(path))
  ref = group.files.find { |f| f.path == File.basename(path) } || group.new_reference(File.basename(path))
  target_names.each do |name|
    target = project.targets.find { |t| t.name == name } or abort("no target #{name}")
    target.add_file_references([ref]) unless target.source_build_phase.files_references.include?(ref)
  end
end

add_file(project, 'Shared/Services/WearSessionService.swift', ['AndroRingTrack (iOS)', 'AndroRingTrackWidget'])
project.save
RUBY
plutil -lint AndroRingTrack.xcodeproj/project.pbxproj
```

- [ ] **Step 3: Build iOS, run tests**

Run the iOS build and unit test commands. Expected: `** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Shared/Services/WearSessionService.swift AndroRingTrack.xcodeproj/project.pbxproj
git commit -m "feat: add WearSessionService for out-of-app session changes"
```

---

### Task 5: App Intents (Start, Stop, Toggle, Get status)

**Files:**
- Delete: `AndroRingTrackWidget/ToggleWearIntent.swift` (moved)
- Create: `Shared/Intents/ToggleWearIntent.swift`
- Create: `Shared/Intents/StartWearIntent.swift`
- Create: `Shared/Intents/StopWearIntent.swift`
- Create: `Shared/Intents/GetWearStatusIntent.swift`
- Create: `Shared/Intents/WearDialog.swift`
- Create: `Shared/Intents/WearSessionError+Intents.swift`
- Modify: `Shared/en.lproj/Localizable.strings`, `Shared/fr.lproj/Localizable.strings`
- Modify: `AndroRingTrack.xcodeproj/project.pbxproj` (scripted; also adds `AndroRingTrackWidget/Views/DurationFormatting.swift` to the app target)

**Interfaces:**
- Consumes: `WearSessionService.shared` (Task 4), `WearOutcome`, `WearStatus` (Task 1), `WearSessionError` (Task 4), `Double.formattedWidgetDuration()` (`AndroRingTrackWidget/Views/DurationFormatting.swift`, hours → e.g. `"6h40"` / `"45min"`), `Record.durationInHours`.
- Produces: `StartWearIntent`, `StopWearIntent`, `ToggleWearIntent`, `GetWearStatusIntent` (all `AppIntent`, `@available(iOS 17.0, *)`, no-arg `init()`); `WearDialog.text(for: WearOutcome) -> String`, `WearDialog.text(for: WearStatus) -> String`. The widget's `Button(intent: ToggleWearIntent())` keeps compiling unchanged.

- [ ] **Step 1: Add localized strings**

Append to `Shared/en.lproj/Localizable.strings`:

```
// INTENTS
"INTENT_START_TITLE" = "Start session";
"INTENT_STOP_TITLE" = "Stop session";
"INTENT_TOGGLE_TITLE" = "Toggle wear status";
"INTENT_STATUS_TITLE" = "Get wear status";
"INTENT_STARTED" = "Session started at %@.";
"INTENT_ALREADY_STARTED" = "Already worn since %@.";
"INTENT_STOPPED" = "Session ended: %@.";
"INTENT_DISCARDED" = "Session cancelled (under 3 min).";
"INTENT_NOT_RUNNING" = "No session in progress.";
"INTENT_STATUS_WORN" = "Worn since %1$@ · %2$@ today (%3$d%% of the %4$d h goal).";
"INTENT_STATUS_OFF" = "Not worn · %1$@ today (%2$d%% of the %3$d h goal).";
"INTENT_ERROR_NOT_AUTHORIZED" = "Open ThermoTrack to allow Health access.";
"INTENT_ERROR_HEALTHKIT" = "Health error: %@";
```

Append to `Shared/fr.lproj/Localizable.strings`:

```
// INTENTS
"INTENT_START_TITLE" = "Démarrer une session";
"INTENT_STOP_TITLE" = "Arrêter la session";
"INTENT_TOGGLE_TITLE" = "Basculer le statut de port";
"INTENT_STATUS_TITLE" = "Obtenir le statut de port";
"INTENT_STARTED" = "Session démarrée à %@.";
"INTENT_ALREADY_STARTED" = "Déjà porté depuis %@.";
"INTENT_STOPPED" = "Session terminée : %@.";
"INTENT_DISCARDED" = "Session annulée (moins de 3 min).";
"INTENT_NOT_RUNNING" = "Aucune session en cours.";
"INTENT_STATUS_WORN" = "Porté depuis %1$@ · %2$@ aujourd'hui (%3$d %% de l'objectif de %4$d h).";
"INTENT_STATUS_OFF" = "Non porté · %1$@ aujourd'hui (%2$d %% de l'objectif de %3$d h).";
"INTENT_ERROR_NOT_AUTHORIZED" = "Ouvrez ThermoTrack pour autoriser l'accès à Santé.";
"INTENT_ERROR_HEALTHKIT" = "Erreur Santé : %@";
```

Check both files still parse: `plutil -lint Shared/en.lproj/Localizable.strings Shared/fr.lproj/Localizable.strings` → `OK` twice.

- [ ] **Step 2: Create `Shared/Intents/WearDialog.swift`**

```swift
//
//  WearDialog.swift
//  ThermoTrack
//

import Foundation

/// Localized sentences spoken/shown by the wear-session intents.
enum WearDialog {
    static func text(for outcome: WearOutcome) -> String {
        switch outcome {
        case .started(let date):
            return String(format: NSLocalizedString("INTENT_STARTED", comment: ""), time(date))
        case .alreadyStarted(let date):
            return String(format: NSLocalizedString("INTENT_ALREADY_STARTED", comment: ""), time(date))
        case .stopped(let record):
            return String(format: NSLocalizedString("INTENT_STOPPED", comment: ""), (record.durationInHours ?? 0).formattedWidgetDuration())
        case .discarded:
            return NSLocalizedString("INTENT_DISCARDED", comment: "")
        case .notRunning:
            return NSLocalizedString("INTENT_NOT_RUNNING", comment: "")
        }
    }

    static func text(for status: WearStatus) -> String {
        let today = (Double(status.todayMinutes) / 60).formattedWidgetDuration()

        if status.isWorn, let start = status.sessionStart {
            return String(
                format: NSLocalizedString("INTENT_STATUS_WORN", comment: ""),
                time(start), today, status.progressPercent, status.goalHours
            )
        }
        return String(
            format: NSLocalizedString("INTENT_STATUS_OFF", comment: ""),
            today, status.progressPercent, status.goalHours
        )
    }

    private static func time(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }
}
```

- [ ] **Step 3: Create `Shared/Intents/WearSessionError+Intents.swift`**

```swift
//
//  WearSessionError+Intents.swift
//  ThermoTrack
//

import AppIntents
import Foundation

/// Lets Shortcuts/Siri show a readable message when an intent throws.
@available(iOS 16.0, *)
extension WearSessionError: CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .healthKitNotAuthorized:
            return "INTENT_ERROR_NOT_AUTHORIZED"
        case .healthKit(let error):
            let message = String(format: NSLocalizedString("INTENT_ERROR_HEALTHKIT", comment: ""), error.errorDescription ?? "")
            return "\(message)"
        }
    }
}
```

- [ ] **Step 4: Create the four intents**

`Shared/Intents/StartWearIntent.swift`:

```swift
//
//  StartWearIntent.swift
//  ThermoTrack
//

import AppIntents

@available(iOS 17.0, *)
struct StartWearIntent: AppIntent {
    static var title: LocalizedStringResource = "INTENT_START_TITLE"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await WearSessionService.shared.start()
        return .result(dialog: "\(WearDialog.text(for: outcome))")
    }
}
```

`Shared/Intents/StopWearIntent.swift`:

```swift
//
//  StopWearIntent.swift
//  ThermoTrack
//

import AppIntents

@available(iOS 17.0, *)
struct StopWearIntent: AppIntent {
    static var title: LocalizedStringResource = "INTENT_STOP_TITLE"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await WearSessionService.shared.stop()
        return .result(dialog: "\(WearDialog.text(for: outcome))")
    }
}
```

`Shared/Intents/ToggleWearIntent.swift`:

```swift
//
//  ToggleWearIntent.swift
//  ThermoTrack
//

import AppIntents

/// Used by the widget's toggle button and exposed in Shortcuts/Siri.
@available(iOS 17.0, *)
struct ToggleWearIntent: AppIntent {
    static var title: LocalizedStringResource = "INTENT_TOGGLE_TITLE"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await WearSessionService.shared.toggle()
        return .result(dialog: "\(WearDialog.text(for: outcome))")
    }
}
```

`Shared/Intents/GetWearStatusIntent.swift`:

```swift
//
//  GetWearStatusIntent.swift
//  ThermoTrack
//

import AppIntents

/// Returns the minutes worn today, so other shortcuts can use the value.
@available(iOS 17.0, *)
struct GetWearStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "INTENT_STATUS_TITLE"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let status = try await WearSessionService.shared.status()
        return .result(value: status.todayMinutes, dialog: "\(WearDialog.text(for: status))")
    }
}
```

- [ ] **Step 5: Move `ToggleWearIntent` and register the new files**

```bash
git rm AndroRingTrackWidget/ToggleWearIntent.swift
ruby <<'RUBY'
require 'xcodeproj'
project = Xcodeproj::Project.open('AndroRingTrack.xcodeproj')

def group_for(project, dir)
  dir.split('/').reduce(project.main_group) do |g, name|
    g.children.find { |c| c.isa == 'PBXGroup' && c.path == name } || g.new_group(name, name)
  end
end

def add_file(project, path, target_names)
  group = group_for(project, File.dirname(path))
  ref = group.files.find { |f| f.path == File.basename(path) } || group.new_reference(File.basename(path))
  target_names.each do |name|
    target = project.targets.find { |t| t.name == name } or abort("no target #{name}")
    target.add_file_references([ref]) unless target.source_build_phase.files_references.include?(ref)
  end
end

old = group_for(project, 'AndroRingTrackWidget').files.find { |f| f.path == 'ToggleWearIntent.swift' }
abort('old ToggleWearIntent.swift reference not found') unless old
old.build_files.each(&:remove_from_project)
old.remove_from_project

app_and_widget = ['AndroRingTrack (iOS)', 'AndroRingTrackWidget']
%w[ToggleWearIntent StartWearIntent StopWearIntent GetWearStatusIntent WearDialog WearSessionError+Intents].each do |name|
  add_file(project, "Shared/Intents/#{name}.swift", app_and_widget)
end
add_file(project, 'AndroRingTrackWidget/Views/DurationFormatting.swift', ['AndroRingTrack (iOS)'])
project.save
RUBY
plutil -lint AndroRingTrack.xcodeproj/project.pbxproj
grep -c "ToggleWearIntent.swift in Sources" AndroRingTrack.xcodeproj/project.pbxproj
```

Expected: `OK`, then `2` (app + widget).

- [ ] **Step 6: Build iOS and watch, run tests**

Run the iOS build, watch build and unit test commands. Expected: `** BUILD SUCCEEDED **` twice, `** TEST SUCCEEDED **`. If the App Intents metadata processor emits warnings about the `INTENT_*_TITLE` keys, note them in the task report; they are not failures.

- [ ] **Step 7: Commit**

```bash
git add -A Shared/Intents Shared/en.lproj/Localizable.strings Shared/fr.lproj/Localizable.strings AndroRingTrackWidget AndroRingTrack.xcodeproj/project.pbxproj
git commit -m "feat: add Start/Stop/Toggle/Status App Intents backed by WearSessionService"
```

---

### Task 6: Siri phrases (`AppShortcutsProvider`), docs, manual verification

**Files:**
- Create: `iOS/Intents/ThermoTrackShortcuts.swift`
- Create: `iOS/fr.lproj/AppShortcuts.strings`
- Modify: `AndroRingTrack.xcodeproj/project.pbxproj` (scripted)
- Modify: `README.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: `StartWearIntent`, `StopWearIntent`, `ToggleWearIntent`, `GetWearStatusIntent` (Task 5), `INTENT_*_TITLE` string keys (Task 5).
- Produces: `ThermoTrackShortcuts: AppShortcutsProvider` (app target only).

- [ ] **Step 1: Create `iOS/Intents/ThermoTrackShortcuts.swift`**

```swift
//
//  ThermoTrackShortcuts.swift
//  ThermoTrack (iOS)
//

import AppIntents

/// Registers the wear-session intents with Siri and the Shortcuts app, no setup needed.
/// French phrases live in `fr.lproj/AppShortcuts.strings`.
@available(iOS 17.0, *)
struct ThermoTrackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWearIntent(),
            phrases: [
                "Start a session in \(.applicationName)",
                "I put on my ring in \(.applicationName)"
            ],
            shortTitle: "INTENT_START_TITLE",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: StopWearIntent(),
            phrases: [
                "Stop my session in \(.applicationName)",
                "I took off my ring in \(.applicationName)"
            ],
            shortTitle: "INTENT_STOP_TITLE",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: ToggleWearIntent(),
            phrases: [
                "Toggle my ring in \(.applicationName)"
            ],
            shortTitle: "INTENT_TOGGLE_TITLE",
            systemImageName: "arrow.triangle.2.circlepath"
        )
        AppShortcut(
            intent: GetWearStatusIntent(),
            phrases: [
                "How long have I worn it today in \(.applicationName)",
                "\(.applicationName) status"
            ],
            shortTitle: "INTENT_STATUS_TITLE",
            systemImageName: "clock"
        )
    }
}
```

- [ ] **Step 2: Create `iOS/fr.lproj/AppShortcuts.strings`**

```
/* Siri / Shortcuts phrases. Keys are the English phrases from ThermoTrackShortcuts.swift. */
"Start a session in ${applicationName}" = "Démarre une session dans ${applicationName}";
"I put on my ring in ${applicationName}" = "J'ai mis mon anneau dans ${applicationName}";
"Stop my session in ${applicationName}" = "Arrête ma session dans ${applicationName}";
"I took off my ring in ${applicationName}" = "J'ai retiré mon anneau dans ${applicationName}";
"Toggle my ring in ${applicationName}" = "Bascule mon anneau dans ${applicationName}";
"How long have I worn it today in ${applicationName}" = "Combien de temps l'ai-je porté aujourd'hui dans ${applicationName}";
"${applicationName} status" = "Statut de ${applicationName}";
```

Run `plutil -lint iOS/fr.lproj/AppShortcuts.strings` → `OK`.

- [ ] **Step 3: Register both files in the app target**

```bash
ruby <<'RUBY'
require 'xcodeproj'
project = Xcodeproj::Project.open('AndroRingTrack.xcodeproj')

def group_for(project, dir)
  dir.split('/').reduce(project.main_group) do |g, name|
    g.children.find { |c| c.isa == 'PBXGroup' && c.path == name } || g.new_group(name, name)
  end
end

app = project.targets.find { |t| t.name == 'AndroRingTrack (iOS)' } or abort('no app target')

intents = group_for(project, 'iOS/Intents')
swift = intents.files.find { |f| f.path == 'ThermoTrackShortcuts.swift' } || intents.new_reference('ThermoTrackShortcuts.swift')
app.add_file_references([swift]) unless app.source_build_phase.files_references.include?(swift)

ios = group_for(project, 'iOS')
variant = ios.children.find { |c| c.isa == 'PBXVariantGroup' && c.name == 'AppShortcuts.strings' } || ios.new_variant_group('AppShortcuts.strings')
unless variant.children.any? { |c| c.name == 'fr' }
  fr = variant.new_reference('fr.lproj/AppShortcuts.strings')
  fr.name = 'fr'
end
app.resources_build_phase.add_file_reference(variant, true)
project.save
RUBY
plutil -lint AndroRingTrack.xcodeproj/project.pbxproj
```

- [ ] **Step 4: Build iOS and watch, run tests**

Run the iOS build, watch build and unit test commands. Expected: `** BUILD SUCCEEDED **` twice, `** TEST SUCCEEDED **`. The App Intents metadata processor validates phrases at build time: every phrase must contain `\(.applicationName)`; a phrase error fails the build.

- [ ] **Step 5: Update the docs**

In `README.md`, under `## Feature suggestions`, change:

```
- [ ] Shortcuts app integration
- [ ] Siri integration
```

to:

```
- [x] Shortcuts app integration
- [x] Siri integration
```

In `CLAUDE.md`, append to the end of the `### Data flow` section (after the `SettingsStore` paragraph):

```markdown
Outside the app's UI (App Intents from Shortcuts/Siri, the widget's toggle button), session changes go through `WearSessionService` (`Shared/Services/WearSessionService.swift`), not `RecordStore`: in an extension process `RecordStore.shared` only holds preview data. The service reads and writes HealthKit directly, applies the rules in `WearSessionLogic` (`Shared/Models/WearSessionLogic.swift`, unit-tested), and reads settings from `AppGroupSettings`, which `SettingsStore` mirrors into the `group.com.astralym.AndroRingTrack` App Group. The intents live in `Shared/Intents/` (iOS 17+); Siri phrases are declared in `iOS/Intents/ThermoTrackShortcuts.swift`.
```

- [ ] **Step 6: Commit**

```bash
git add iOS/Intents iOS/fr.lproj AndroRingTrack.xcodeproj/project.pbxproj README.md CLAUDE.md
git commit -m "feat: register Siri phrases for wear-session intents"
```

- [ ] **Step 7: Manual verification checklist (on a device or simulator with iOS 17+)**

Report each item's result; do not tick items that could not be run.

1. Fresh install: before granting Health access, run "Start session" from Shortcuts → error "Open ThermoTrack to allow Health access.", no sample written.
2. Grant access, open the app once (mirrors settings). Enable both notifications in Settings.
3. Shortcuts → "Start session" → dialog "Session started at HH:MM"; Health app shows an open sample; widget shows worn; pending notification `notifyEnd` exists, `reminderStart` removed.
4. Run "Start session" again → "Already worn since HH:MM", still one sample.
5. "Stop session" within 3 min → "Session cancelled (under 3 min)", sample gone, `reminderStart` pending.
6. Start, wait ≥ 3 min, "Toggle wear status" → "Session ended: …", sample stored.
7. "Get wear status" → dialog with today's time and %, returned value usable in a following "Show result" action.
8. Widget toggle button → same state change, and notifications now updated (previously skipped).
9. Siri in English and French: "Start a session in ThermoTrack" / "Démarre une session dans ThermoTrack".
10. With the app open in foreground, trigger a start via Siri → Today view updates (observer query).
11. With the iPhone locked, run "Start a session in ThermoTrack" via Siri → Siri asks to unlock, then the session starts.
```
