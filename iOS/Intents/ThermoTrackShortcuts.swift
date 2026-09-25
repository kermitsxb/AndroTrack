//
//  ThermoTrackShortcuts.swift
//  ThermoTrack (iOS)
//

import AppIntents

/// Registers the wear-session intents with Siri and the Shortcuts app, no setup needed.
/// French phrases live in `fr.lproj/AppShortcuts.strings`.
@available(iOS 17.0, *)
struct ThermoTrackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWearIntent(),
            phrases: [
                "Start a session in \(.applicationName)",
                "I put on my ring in \(.applicationName)"
            ],
            shortTitle: "INTENT_START_TITLE",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: StopWearIntent(),
            phrases: [
                "Stop my session in \(.applicationName)",
                "I took off my ring in \(.applicationName)"
            ],
            shortTitle: "INTENT_STOP_TITLE",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: ToggleWearIntent(),
            phrases: [
                "Toggle my ring in \(.applicationName)"
            ],
            shortTitle: "INTENT_TOGGLE_TITLE",
            systemImageName: "arrow.triangle.2.circlepath"
        )
        AppShortcut(
            intent: GetWearStatusIntent(),
            phrases: [
                "How long have I worn it today in \(.applicationName)",
                "\(.applicationName) status"
            ],
            shortTitle: "INTENT_STATUS_TITLE",
            systemImageName: "clock"
        )
    }
}
