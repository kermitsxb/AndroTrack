import SwiftUI
import WidgetKit

extension View {
    @ViewBuilder
    func widgetBackgroundCompat() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(.fill.tertiary, for: .widget)
        } else {
            self
        }
    }
}
