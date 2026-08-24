import WidgetKit
import SwiftUI

@main
struct AndroRingTrackWidgetBundle: WidgetBundle {
    var body: some Widget {
        WearStatusWidget()
        if #available(iOS 16.0, *) {
            WearStatusAccessoryWidget()
        }
    }
}
