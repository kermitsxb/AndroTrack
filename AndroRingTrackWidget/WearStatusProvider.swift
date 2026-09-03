import WidgetKit
import Foundation

struct WearStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> WearStatusEntry {
        WearStatusEntry(
            date: Date(),
            state: .off,
            sessionStart: nil,
            todayDurationInHours: 1.5,
            goalInHours: currentGoalInHours(),
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

        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date().addingTimeInterval(-2 * 24 * 60 * 60)
        HealthKitService.shared.fetchRecords(since: twoDaysAgo) { records, error in
            if let error = error {
                AppLogger.error(context: "Widget", "Failed to fetch records: \(error.errorDescription ?? "unknown")")
                completion(self.unauthorizedEntry())
                return
            }

            let allRecords = records ?? []
            let now = Date()
            let dayStart = Calendar.current.startOfDay(for: now)
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? now
            let todayOverlapping = allRecords.filter { record in
                guard let start = record.start else { return false }
                let end = record.end ?? now
                return start < dayEnd && end > dayStart
            }
            let today = Day(date: now, records: todayOverlapping)
            let openRecord = allRecords.first(where: { $0.end == nil })
            let state: RingState = openRecord != nil ? .worn : .off
            let sessionStart = openRecord?.start

            let entry = WearStatusEntry(
                date: Date(),
                state: state,
                sessionStart: sessionStart,
                todayDurationInHours: today.duration,
                goalInHours: self.currentGoalInHours(),
                isAuthorized: true
            )

            DispatchQueue.main.async {
                completion(entry)
            }
        }
    }

    private func currentGoalInHours() -> Int {
        let suite = UserDefaults(suiteName: "group.com.astralym.AndroRingTrack")
        if let stored = suite?.object(forKey: "sessionLength") as? Int {
            return stored
        }
        return 15
    }

    private func unauthorizedEntry() -> WearStatusEntry {
        WearStatusEntry(
            date: Date(),
            state: .off,
            sessionStart: nil,
            todayDurationInHours: 0,
            goalInHours: currentGoalInHours(),
            isAuthorized: false
        )
    }
}
