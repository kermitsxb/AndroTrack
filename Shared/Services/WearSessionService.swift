//
//  WearSessionService.swift
//  ThermoTrack
//

import Foundation
import HealthKit
import WidgetKit

enum WearSessionError: Error {
    case healthKitNotAuthorized
    /// The device is locked, so HealthKit's encrypted store can't be read (HKError.errorDatabaseInaccessible).
    case healthDataLocked
    case healthKit(HealthKitServiceError)
}

/// Starts/stops wear sessions straight against HealthKit, for callers that run outside the
/// app's UI (App Intents from Shortcuts/Siri, the widget button). `RecordStore.shared` can't be
/// used there: in an extension process it only holds preview data. Changes made here reach a
/// running app through `RecordStore`'s HealthKit observer query.
///
/// An `actor` so concurrent callers (a Siri intent racing a widget tap) are serialized: each
/// call's read-decide-write sequence completes before the next one starts, which prevents two
/// callers from both reading "no open session" and both writing a start.
actor WearSessionService {
    static let shared = WearSessionService()

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
        let since = Calendar.current.date(byAdding: .day, value: -WearSessionLogic.fetchWindowDays, to: Date())
            ?? Date().addingTimeInterval(-Double(WearSessionLogic.fetchWindowDays) * 24 * 60 * 60)

        return try await withCheckedThrowingContinuation { continuation in
            healthKit.fetchRecords(since: since) { records, error in
                if let error = error {
                    AppLogger.error(context: "WearSessionService", "Failed to fetch records: \(error.errorDescription ?? "unknown")")
                    continuation.resume(throwing: Self.wearSessionError(for: error))
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
                    continuation.resume(throwing: Self.wearSessionError(for: error))
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
                    continuation.resume(throwing: Self.wearSessionError(for: error))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// The device being locked surfaces from HealthKit as `HealthKitServiceError.Failure`
    /// wrapping an `HKError.errorDatabaseInaccessible`; report that distinctly so the intent can
    /// show a message about unlocking rather than a raw HealthKit error.
    private static func wearSessionError(for error: HealthKitServiceError) -> WearSessionError {
        if case .Failure(let underlying) = error, (underlying as? HKError)?.code == .errorDatabaseInaccessible {
            return .healthDataLocked
        }
        return .healthKit(error)
    }
}
