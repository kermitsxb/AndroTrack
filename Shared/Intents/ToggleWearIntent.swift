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
