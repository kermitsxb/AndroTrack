//
//  WearDialog.swift
//  ThermoTrack
//

import Foundation

/// Localized sentences spoken/shown by the wear-session intents.
enum WearDialog {
    static func text(for outcome: WearOutcome) -> String {
        switch outcome {
        case .started(let date):
            return String(format: NSLocalizedString("INTENT_STARTED", comment: ""), time(date))
        case .alreadyStarted(let date):
            return String(format: NSLocalizedString("INTENT_ALREADY_STARTED", comment: ""), time(date))
        case .stopped(let record):
            return String(format: NSLocalizedString("INTENT_STOPPED", comment: ""), (record.durationInHours ?? 0).formattedWidgetDuration())
        case .discarded:
            return NSLocalizedString("INTENT_DISCARDED", comment: "")
        case .notRunning:
            return NSLocalizedString("INTENT_NOT_RUNNING", comment: "")
        }
    }

    static func text(for status: WearStatus) -> String {
        let today = (Double(status.todayMinutes) / 60).formattedWidgetDuration()

        if status.isWorn, let start = status.sessionStart {
            return String(
                format: NSLocalizedString("INTENT_STATUS_WORN", comment: ""),
                time(start), today, status.progressPercent, status.goalHours
            )
        }
        return String(
            format: NSLocalizedString("INTENT_STATUS_OFF", comment: ""),
            today, status.progressPercent, status.goalHours
        )
    }

    private static func time(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }
}
