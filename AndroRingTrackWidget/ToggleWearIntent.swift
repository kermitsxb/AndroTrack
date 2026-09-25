import AppIntents
import Foundation

@available(iOS 17.0, *)
struct ToggleWearIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle wear status"

    func perform() async throws -> some IntentResult {
        // The widget runs in a separate process from the main app, so
        // RecordStore.shared here is a fresh instance holding preview data.
        // WearSession reads ground truth straight from HealthKit instead.
        //
        // Deliberate simplification: widget-triggered toggles do not
        // schedule/cancel the local notifications that app-triggered toggles do.
        if case .alreadyWorn = try await WearSession.start() {
            _ = try await WearSession.stop()
        }
        return .result()
    }
}
