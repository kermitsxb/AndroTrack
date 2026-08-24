import WidgetKit
import SwiftUI

struct WearStatusWidget: Widget {
    let kind: String = "WearStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WearStatusProvider()) { entry in
            WearStatusWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("WIDGET_DISPLAY_NAME", comment: ""))
        .description(NSLocalizedString("WIDGET_DESCRIPTION", comment: ""))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
