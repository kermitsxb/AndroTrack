import WidgetKit
import SwiftUI

@main
struct ThermoTrackWidgetBundle: WidgetBundle {
    var body: some Widget {
        WearStatusWidget()
        if #available(iOS 16.0, *) {
            WearStatusAccessoryWidget()
        }
    }
}
