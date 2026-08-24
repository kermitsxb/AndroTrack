import AppIntents
import WidgetKit

@available(iOS 17.0, *)
struct ToggleWearIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle wear status"

    func perform() async throws -> some IntentResult {
        if RecordStore.shared.state == .worn {
            RecordStore.shared.markAsRemoved()
        } else {
            RecordStore.shared.markAsWorn()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
