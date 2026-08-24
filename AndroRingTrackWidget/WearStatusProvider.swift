import WidgetKit
import Foundation

struct WearStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> WearStatusEntry {
        WearStatusEntry(
            date: Date(),
            state: .off,
            sessionStart: nil,
            todayDurationInHours: 1.5,
            goalInHours: SettingsStore.shared.sessionLength,
            isAuthorized: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WearStatusEntry) -> Void) {
        buildEntry { entry in
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WearStatusEntry>) -> Void) {
        buildEntry { entry in
            let reloadDelay: TimeInterval = entry.state == .worn ? 15 * 60 : 60 * 60
            let reloadDate = Date().addingTimeInterval(reloadDelay)
            completion(Timeline(entries: [entry], policy: .after(reloadDate)))
        }
    }

    private func buildEntry(completion: @escaping (WearStatusEntry) -> Void) {
        guard HealthKitService.shared.healthKitAuthorizationStatus == .sharingAuthorized else {
            completion(unauthorizedEntry())
            return
        }

        HealthKitService.shared.fetchRecords { records, error in
            if let error = error {
                AppLogger.error(context: "Widget", "Failed to fetch records: \(error.errorDescription ?? "unknown")")
                completion(self.unauthorizedEntry())
                return
            }

            let allRecords = records ?? []
            let today = Day(records: allRecords.filter {
                $0.start != nil && Calendar.current.isDateInToday($0.start!)
            })
            let lastRecord = allRecords.last
            let state: RingState = (lastRecord != nil && lastRecord!.end == nil) ? .worn : .off
            let sessionStart = state == .worn ? lastRecord?.start : nil

            let entry = WearStatusEntry(
                date: Date(),
                state: state,
                sessionStart: sessionStart,
                todayDurationInHours: today.duration,
                goalInHours: SettingsStore.shared.sessionLength,
                isAuthorized: true
            )

            DispatchQueue.main.async {
                completion(entry)
            }
        }
    }

    private func unauthorizedEntry() -> WearStatusEntry {
        WearStatusEntry(
            date: Date(),
            state: .off,
            sessionStart: nil,
            todayDurationInHours: 0,
            goalInHours: SettingsStore.shared.sessionLength,
            isAuthorized: false
        )
    }
}
