//
//  Day.swift
//  ThermoTrack
//
//  Created by Benoit Sida on 2021-07-14.
//

import Foundation

struct Day {
    var date: Date = Date()
    var records: [Record] = []

    /// Sum of the portion of each record's duration that actually falls within `date`.
    /// A record is clipped to the day's boundaries so a session spanning multiple days
    /// contributes its hours to each day it overlaps, instead of dumping its entire
    /// duration onto the day it started on.
    var duration: Double {
        records.reduce(0, { $0 + durationInHours(of: $1) })
    }

    private func durationInHours(of record: Record) -> Double {
        guard let start = record.start else { return 0 }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }

        let end = record.end ?? Date()
        let clippedStart = max(start, dayStart)
        let clippedEnd = min(end, dayEnd)

        guard clippedEnd > clippedStart else { return 0 }
        return clippedEnd.timeIntervalSince(clippedStart) / DurationUnit.hours.rawValue
    }

    /// The day used for the "today" goal (Today view, widget, end-of-session notification).
    ///
    /// Records overlapping today are clipped to the day like any other day, with one exception:
    /// a session that started on a previous day and is already over does not count. Its hours
    /// belong to the cycle it started in; once the ring came off, a new cycle starts at zero
    /// and the full session length has to be worn again. An ongoing session is always kept,
    /// even if it started on a previous day, so the current wear time stays visible.
    static func today(from records: [Record], now: Date = Date()) -> Day {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return Day(date: now, records: [])
        }

        let relevant = records.filter { record in
            guard let start = record.start else { return false }
            let end = record.end ?? now
            let overlapsToday = start < dayEnd && end > dayStart
            let finishedSpillover = record.end != nil && start < dayStart
            return overlapsToday && !finishedSpillover
        }

        return Day(date: now, records: relevant)
    }

    func durationAsProgress(goal: Int) -> Double {
        return (duration / Double(goal)) * 100
    }
    
    func estimatedEnd(forDuration sessionLength: Int) -> Date? {
        return Calendar.current.date(byAdding: .second, value: Int((Double(sessionLength) - duration) * 3600), to: Date())
    }
}

extension Day: CustomStringConvertible {
    var description: String {
        "{ records: \(records.count), date: \(records.count != 0 ? records.first!.start!.format() : "unknown") }"
    }
}
