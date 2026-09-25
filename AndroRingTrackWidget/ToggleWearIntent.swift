import AppIntents
import Foundation

@available(iOS 17.0, *)
struct ToggleWearIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle wear status"

    func perform() async throws -> some IntentResult {
        // The widget runs in a separate process from the main app, so
        // RecordStore.shared and SettingsStore.shared here hold preview/default data.
        // WearSession reads ground truth straight from HealthKit, and settings come
        // from the App Group that SettingsStore mirrors them into.
        let settings = AppGroupSettings.notifications

        if case .alreadyWorn = try await WearSession.start() {
            _ = try await WearSession.stop()
            // Same call as RecordStore.markAsRemoved(), stored or discarded alike.
            Notifications.scheduleReminderStart(settings: settings)
        } else {
            // Same call as RecordStore.markAsWorn(), fed with today's real records.
            let records = try await WearSession.fetchRecords()
            Notifications.scheduleNotifyEnd(
                today: Day.today(from: records),
                sessionLength: AppGroupSettings.sessionLength,
                settings: settings
            )
        }
        return .result()
    }
}
