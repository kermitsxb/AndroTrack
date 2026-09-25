//
//  StopWearIntent.swift
//  ThermoTrack
//

import AppIntents

@available(iOS 17.0, *)
struct StopWearIntent: AppIntent {
    static var title: LocalizedStringResource = "INTENT_STOP_TITLE"
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await WearSessionService.shared.stop()
        return .result(dialog: "\(WearDialog.text(for: outcome))")
    }
}
