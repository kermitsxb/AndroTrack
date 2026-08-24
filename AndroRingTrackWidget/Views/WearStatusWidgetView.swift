import SwiftUI
import WidgetKit

struct WearStatusWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: WearStatusEntry

    var body: some View {
        if !entry.isAuthorized {
            unauthorizedView
        } else if family == .systemMedium {
            mediumView
        } else {
            smallView
        }
    }

    private var unauthorizedView: some View {
        VStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle")
                .font(.title2)
            Text("WIDGET_UNAUTHORIZED")
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusIcon
            Text(entry.state == .worn ? "REMOVE" : "WEAR")
                .font(.headline)
            durationText
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                statusIcon
                Text(entry.state == .worn ? "REMOVE" : "WEAR")
                    .font(.headline)
                durationText
            }
            Spacer()
            ProgressView(value: min(entry.todayDurationInHours / Double(max(entry.goalInHours, 1)), 1.0))
                .progressViewStyle(.circular)
        }
        .padding()
    }

    private var statusIcon: some View {
        Image(systemName: entry.state == .worn ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundColor(entry.state == .worn ? .accentColor : .secondary)
    }

    @ViewBuilder
    private var durationText: some View {
        if entry.state == .worn, let start = entry.sessionStart {
            Text(start, style: .timer)
                .font(.caption)
                .monospacedDigit()
        } else {
            Text(entry.todayDurationInHours.formattedWidgetDuration())
                .font(.caption)
        }
    }
}
