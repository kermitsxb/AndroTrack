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
