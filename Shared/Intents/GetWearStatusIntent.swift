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
