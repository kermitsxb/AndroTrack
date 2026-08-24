import WidgetKit
import SwiftUI

@available(iOS 16.0, *)
struct WearStatusAccessoryWidget: Widget {
    let kind: String = "WearStatusAccessoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WearStatusProvider()) { entry in
            WearStatusAccessoryView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("WIDGET_DISPLAY_NAME", comment: ""))
        .description(NSLocalizedString("WIDGET_DESCRIPTION", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
