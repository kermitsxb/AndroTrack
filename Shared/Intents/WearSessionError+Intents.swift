//
//  WearSessionError+Intents.swift
//  ThermoTrack
//

import AppIntents
import Foundation

/// Lets Shortcuts/Siri show a readable message when an intent throws.
@available(iOS 16.0, *)
extension WearSessionError: CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .healthKitNotAuthorized:
            return "INTENT_ERROR_NOT_AUTHORIZED"
        case .healthDataLocked:
            return "INTENT_ERROR_LOCKED"
        case .healthKit:
            // The technical detail is already logged by WearSessionService via AppLogger.
            return "INTENT_ERROR_HEALTHKIT"
        }
    }
}
