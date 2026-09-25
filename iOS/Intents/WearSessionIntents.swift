//
//  WearSessionIntents.swift
//  ThermoTrack
//
//  Siri and Shortcuts actions. They run in the app process (launched in the background),
//  so after writing to HealthKit they refresh RecordStore and reschedule the local
//  notifications exactly like the in-app toggle does.
//

import AppIntents
import Foundation

@available(iOS 16.0, *)
struct StartWearSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "INTENT_START_TITLE"
    static var description = IntentDescription("INTENT_START_DESCRIPTION")
    // HealthKit data is unavailable while the device is locked.
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await WearIntentSupport.run { try await WearSession.start() }

        switch outcome {
        case .alreadyWorn(let record):
            let elapsed = WearIntentSupport.formatHours(WearIntentSupport.hours(since: record.start))
            return .result(dialog: WearIntentSupport.dialog("INTENT_ALREADY_WORN", elapsed))
        case .started:
            await WearIntentSupport.syncAppState { Notifications.scheduleNotifyEnd() }
            let status = try await WearIntentSupport.currentStatus()
            if let end = status.estimatedEnd, status.remaining > 0 {
                return .result(dialog: WearIntentSupport.dialog("INTENT_STARTED", WearIntentSupport.formatTime(end)))
            }
            return .result(dialog: WearIntentSupport.dialog("INTENT_STARTED_GOAL_DONE"))
        }
    }
}

@available(iOS 16.0, *)
struct StopWearSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "INTENT_STOP_TITLE"
    static var description = IntentDescription("INTENT_STOP_DESCRIPTION")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await WearIntentSupport.run { try await WearSession.stop() }

        switch outcome {
        case .notWorn:
            return .result(dialog: WearIntentSupport.dialog("INTENT_NOT_WORN"))
        case .discarded:
            await WearIntentSupport.syncAppState { Notifications.scheduleReminderStart() }
            return .result(dialog: WearIntentSupport.dialog("INTENT_DISCARDED"))
        case .stopped(let record):
            await WearIntentSupport.syncAppState { Notifications.scheduleReminderStart() }
            let duration = WearIntentSupport.formatHours(record.durationInHours ?? 0)
            return .result(dialog: WearIntentSupport.dialog("INTENT_STOPPED", duration))
        }
    }
}

@available(iOS 16.0, *)
struct GetWearStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "INTENT_STATUS_TITLE"
    static var description = IntentDescription("INTENT_STATUS_DESCRIPTION")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    /// Returns whether the ring is currently worn, for use in Shortcuts automations.
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let status = try await WearIntentSupport.currentStatus()
        let today = WearIntentSupport.formatHours(status.wornToday)
        let remaining = WearIntentSupport.formatHours(status.remaining)
        let goalDone = status.remaining <= 0

        let dialog: IntentDialog
        if status.isWorn {
            let session = WearIntentSupport.formatHours(status.currentSessionDuration ?? 0)
            dialog = goalDone
                ? WearIntentSupport.dialog("INTENT_STATUS_WORN_GOAL_DONE", session)
                : WearIntentSupport.dialog("INTENT_STATUS_WORN", session, remaining)
        } else {
            dialog = goalDone
                ? WearIntentSupport.dialog("INTENT_STATUS_OFF_GOAL_DONE", today)
                : WearIntentSupport.dialog("INTENT_STATUS_OFF", today, remaining)
        }

        return .result(value: status.isWorn, dialog: dialog)
    }
}

@available(iOS 16.0, *)
struct ThermoTrackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWearSessionIntent(),
            phrases: [
                "Start a session in \(.applicationName)",
                "Start my \(.applicationName) session",
                "I put my ring on in \(.applicationName)",
            ],
            shortTitle: "SHORTCUT_START",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: StopWearSessionIntent(),
            phrases: [
                "Stop my session in \(.applicationName)",
                "Stop my \(.applicationName) session",
                "I took my ring off in \(.applicationName)",
            ],
            shortTitle: "SHORTCUT_STOP",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: GetWearStatusIntent(),
            phrases: [
                "How is my \(.applicationName) session going",
                "\(.applicationName) status",
                "Am I wearing my ring in \(.applicationName)",
            ],
            shortTitle: "SHORTCUT_STATUS",
            systemImageName: "clock"
        )
    }
}

/// Error surfaced to Siri/Shortcuts when HealthKit can't be reached.
@available(iOS 16.0, *)
struct WearIntentError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource { "INTENT_ERROR_HEALTHKIT" }
}

@available(iOS 16.0, *)
enum WearIntentSupport {
    /// Runs a HealthKit operation, turning any failure into a user-facing error.
    static func run<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw WearIntentError()
        }
    }

    static func currentStatus() async throws -> WearStatus {
        let records = try await run { try await WearSession.fetchRecords() }
        return WearStatus(records: records, sessionLength: SettingsStore.shared.sessionLength)
    }

    /// Reloads RecordStore from HealthKit, then runs `notifications` so that the
    /// scheduling code (which reads RecordStore) sees the new session state.
    @MainActor
    static func syncAppState(_ notifications: @escaping () -> Void) async {
        await withCheckedContinuation { continuation in
            RecordStore.shared.refreshHealthData {
                notifications()
                continuation.resume()
            }
        }
    }

    static func dialog(_ key: String, _ arguments: CVarArg...) -> IntentDialog {
        let text = String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
        return IntentDialog(stringLiteral: text)
    }

    static func hours(since date: Date?) -> Double {
        guard let date = date else { return 0 }
        return Date().timeIntervalSince(date) / DurationUnit.hours.rawValue
    }

    /// Spoken-friendly duration, e.g. "14 hr, 12 min" / "14 h 12 min".
    static func formatHours(_ hours: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = hours >= 1 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        return formatter.string(from: (hours * 3600).rounded()) ?? ""
    }

    static func formatTime(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }
}
