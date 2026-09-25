//
//  WearStatus.swift
//  ThermoTrack
//

import Foundation

/// Snapshot of the current wear state, derived from the HealthKit records.
/// Used by the Siri/Shortcuts intents to answer "start", "stop" and "status".
struct WearStatus {
    let isWorn: Bool
    /// The ongoing session, if any.
    let currentSession: Record?
    /// Hours of the ongoing session so far.
    let currentSessionDuration: Double?
    /// Hours counting toward today's goal (same rules as `Day.today`).
    let wornToday: Double
    /// Hours left to reach today's goal, never negative.
    let remaining: Double
    /// When today's goal will be reached if the ring stays on. Nil when not worn.
    let estimatedEnd: Date?

    init(records: [Record], sessionLength: Int, now: Date = Date()) {
        let open = records.last(where: { $0.start != nil && $0.end == nil })
        currentSession = open
        isWorn = open != nil
        currentSessionDuration = open?.start.map { now.timeIntervalSince($0) / DurationUnit.hours.rawValue }

        wornToday = Self.hoursToday(Day.today(from: records, now: now), now: now)
        remaining = max(0, Double(sessionLength) - wornToday)
        estimatedEnd = isWorn ? now.addingTimeInterval(remaining * DurationUnit.hours.rawValue) : nil
    }

    /// `Day.duration` measures open records against the real clock; recompute against `now`
    /// so the snapshot stays consistent (and testable) for a given instant.
    private static func hoursToday(_ day: Day, now: Date) -> Double {
        let dayStart = Calendar.current.startOfDay(for: now)
        return day.records.reduce(0) { total, record in
            guard let start = record.start else { return total }
            let end = min(record.end ?? now, now)
            let clippedStart = max(start, dayStart)
            guard end > clippedStart else { return total }
            return total + end.timeIntervalSince(clippedStart) / DurationUnit.hours.rawValue
        }
    }
}
