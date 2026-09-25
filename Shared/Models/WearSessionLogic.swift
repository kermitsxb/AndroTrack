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

    /// An ongoing session is stored with end == start, so any fetch window looking for an open
    /// session must reach back to the start of the longest plausible one, not just today. Shared
    /// by `WearSessionService` and the widget's own HealthKit fetch so both agree on what counts
    /// as an open session.
    static let fetchWindowDays = 7

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
