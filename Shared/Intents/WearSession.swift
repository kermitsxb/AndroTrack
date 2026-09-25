//
//  WearSession.swift
//  ThermoTrack
//

import Foundation
import WidgetKit

/// Starts and stops wear sessions straight against HealthKit, for code running outside
/// the app's UI (widget, Siri, Shortcuts) where `RecordStore.shared` may not be loaded.
/// Replicates `RecordStore`'s rules: one open session at a time, and a session under
/// 3 minutes is treated as an accidental toggle and dropped.
///
/// Does not schedule notifications: callers running in the app process handle that.
enum WearSession {
    enum StartOutcome {
        case started
        case alreadyWorn(Record)
    }

    enum StopOutcome {
        case stopped(Record)
        /// Under 3 minutes: the sample was deleted instead of stored.
        case discarded
        case notWorn
    }

    static func fetchRecords() async throws -> [Record] {
        try await withCheckedThrowingContinuation { continuation in
            HealthKitService.shared.fetchRecords { records, error in
                if let error = error {
                    AppLogger.error(context: "WearSession", "Failed to fetch records: \(error.errorDescription ?? "unknown")")
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: records ?? [])
                }
            }
        }
    }

    static func start() async throws -> StartOutcome {
        if let openRecord = try await WearStatus.openSession(in: fetchRecords()) {
            return .alreadyWorn(openRecord)
        }

        let start = Date()
        try await storeRecord(Record(start: start))

        // Another caller (e.g. Siri in the app and the widget in its extension) may have
        // started a session at the same moment: both saw "not worn" and both wrote a sample.
        // The earliest one wins; the later caller removes its own and reports it as already worn.
        if let earlier = try await WearStatus.concurrentStart(before: start, in: fetchRecords()) {
            AppLogger.info(context: "WearSession", "Concurrent start detected, dropping duplicate session")
            try await removeRecord(at: start)
            WidgetCenter.shared.reloadAllTimelines()
            return .alreadyWorn(earlier)
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .started
    }

    static func stop() async throws -> StopOutcome {
        guard let openRecord = try await WearStatus.openSession(in: fetchRecords()) else {
            return .notWorn
        }

        openRecord.markEnded()
        let outcome: StopOutcome
        if (openRecord.durationInMinutes ?? 0) < 3, let start = openRecord.start {
            try await removeRecord(at: start)
            outcome = .discarded
        } else {
            try await storeRecord(openRecord)
            outcome = .stopped(openRecord)
        }

        WidgetCenter.shared.reloadAllTimelines()
        return outcome
    }

    private static func storeRecord(_ record: Record) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            HealthKitService.shared.storeRecord(record: record) { error in
                if let error = error {
                    AppLogger.error(context: "WearSession", "Failed to store record: \(error.errorDescription ?? "unknown")")
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static func removeRecord(at start: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            HealthKitService.shared.removeRecord(at: start) { error in
                if let error = error {
                    AppLogger.error(context: "WearSession", "Failed to remove record: \(error.errorDescription ?? "unknown")")
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
