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
        case .healthKit(let error):
            let message = String(format: NSLocalizedString("INTENT_ERROR_HEALTHKIT", comment: ""), error.errorDescription ?? "")
            return "\(message)"
        }
    }
}
