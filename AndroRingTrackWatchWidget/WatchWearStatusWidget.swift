import WidgetKit
import SwiftUI

struct WatchWearStatusWidget: Widget {
    let kind: String = "WatchWearStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WearStatusProvider()) { entry in
            WatchWearStatusAccessoryView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("WIDGET_DISPLAY_NAME", comment: ""))
        .description(NSLocalizedString("WIDGET_DESCRIPTION", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
