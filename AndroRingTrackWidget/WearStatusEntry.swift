import WidgetKit
import Foundation

struct WearStatusEntry: TimelineEntry {
    let date: Date
    let state: RingState
    let sessionStart: Date?
    let todayDurationInHours: Double
    let goalInHours: Int
    let isAuthorized: Bool
}
