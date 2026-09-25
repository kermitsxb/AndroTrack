//
//  AppGroupSettings.swift
//  ThermoTrack
//

import Foundation

/// Settings shared with processes that can't use `SettingsStore` (the widget extension,
/// whose toggle button starts/stops sessions). `SettingsStore` writes them; everyone else
/// reads them from here. Until the app has written a value, readers get the same defaults
/// as `SettingsStore`.
enum AppGroupSettings {
    static let suiteName = "group.com.astralym.AndroRingTrack"

    private static let sessionLengthKey = "sessionLength"
    private static let notificationsKey = "notifications"

    private static var suite: UserDefaults? { UserDefaults(suiteName: suiteName) }

    static var sessionLength: Int {
        (suite?.object(forKey: sessionLengthKey) as? Int) ?? 15
    }

    static var notifications: NotificationsSettings {
        guard let suite = suite, let stored: NotificationsSettings = suite.typed(forKey: notificationsKey) else {
            return NotificationsSettings()
        }
        return stored
    }

    static func mirror(sessionLength: Int) {
        suite?.set(sessionLength, forKey: sessionLengthKey)
    }

    static func mirror(notifications: NotificationsSettings) {
        do {
            try suite?.trySet(notifications, forKey: notificationsKey)
        } catch {
            AppLogger.warning(context: "AppGroupSettings", "Unable to mirror notifications settings")
        }
    }
}
