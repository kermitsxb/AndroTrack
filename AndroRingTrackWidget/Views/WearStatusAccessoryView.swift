import SwiftUI
import WidgetKit

@available(iOS 16.0, *)
struct WearStatusAccessoryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WearStatusEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        default:
            rectangular
        }
    }

    private var circular: some View {
        Gauge(
            value: min(entry.todayDurationInHours / Double(max(entry.goalInHours, 1)), 1.0)
        ) {
            Image(systemName: entry.state == .worn ? "checkmark.circle.fill" : "circle")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.state == .worn ? "REMOVE" : "WEAR")
                .font(.headline)
            if entry.state == .worn, let start = entry.sessionStart {
                Text(start, style: .timer)
                    .font(.caption2)
            } else {
                Text(entry.todayDurationInHours.formattedWidgetDuration())
                    .font(.caption2)
            }
        }
    }
}
