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
