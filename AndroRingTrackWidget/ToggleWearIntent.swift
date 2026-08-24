import AppIntents
import Foundation
import WidgetKit

@available(iOS 17.0, *)
struct ToggleWearIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle wear status"

    func perform() async throws -> some IntentResult {
        // The widget runs in a separate process from the main app, so
        // RecordStore.shared here is a fresh instance holding preview data.
        // Read ground truth straight from HealthKit instead, and write back
        // through HealthKitService, replicating RecordStore's two rules.
        //
        // Deliberate simplification: widget-triggered toggles do not
        // schedule/cancel the local notifications that app-triggered toggles do.
        let records = try await fetchRecords()

        if let openRecord = records.first(where: { $0.end == nil }) {
            openRecord.markEnded()

            if (openRecord.durationInMinutes ?? 0) < 3, let start = openRecord.start {
                // Treated as an accidental toggle: drop the sample entirely.
                try await removeRecord(at: start)
            } else {
                try await storeRecord(openRecord)
            }
        } else {
            try await storeRecord(Record(start: Date()))
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }

    private func fetchRecords() async throws -> [Record] {
        try await withCheckedThrowingContinuation { continuation in
            HealthKitService.shared.fetchRecords { records, error in
                if let error = error {
                    AppLogger.error(context: "ToggleWearIntent", "Failed to fetch records: \(error.errorDescription ?? "unknown")")
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: records ?? [])
                }
            }
        }
    }

    private func storeRecord(_ record: Record) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            HealthKitService.shared.storeRecord(record: record) { error in
                if let error = error {
                    AppLogger.error(context: "ToggleWearIntent", "Failed to store record: \(error.errorDescription ?? "unknown")")
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func removeRecord(at start: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            HealthKitService.shared.removeRecord(at: start) { error in
                if let error = error {
                    AppLogger.error(context: "ToggleWearIntent", "Failed to remove record: \(error.errorDescription ?? "unknown")")
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
