import Foundation

extension Double {
    /// Formats a duration in hours as e.g. "2h05" or "45min", for compact widget display.
    func formattedWidgetDuration() -> String {
        let totalMinutes = Int((self * 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h\(String(format: "%02d", minutes))" : "\(minutes)min"
    }
}
