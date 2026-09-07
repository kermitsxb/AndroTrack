//
//  DayTests.swift
//  AndroRingTrackTests
//

import XCTest

final class DayTests: XCTestCase {
    private let calendar = Calendar.current
    private var todayStart: Date { calendar.startOfDay(for: Date()) }

    /// Builds a date relative to the start of today: `at(-1, 20, 30)` is yesterday at 20:30.
    private func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(byAdding: .minute, value: dayOffset * 1440 + hour * 60 + minute, to: todayStart)!
    }

    // MARK: - Day.today(from:)

    func testFinishedSessionStartedOnPreviousDayIsExcludedFromToday() {
        // 42h session that ended at 01:30 today, then a new session started at 09:30.
        let previous = Record(start: at(-2, 7, 30), end: at(0, 1, 30))
        let current = Record(start: at(0, 9, 30), end: nil)

        let today = Day.today(from: [previous, current], now: at(0, 9, 30))

        XCTAssertEqual(today.records.count, 1)
        XCTAssertTrue(today.records.first === current)
    }

    func testOngoingSessionStartedOnPreviousDayIsKeptAndClipped() {
        let ongoing = Record(start: at(-1, 20, 0), end: nil)

        let today = Day.today(from: [ongoing], now: at(0, 9, 30))

        XCTAssertEqual(today.records.count, 1)
        // Clipped at midnight: only the part of the session inside today counts.
        let sinceMidnight = Date().timeIntervalSince(todayStart) / 3600
        XCTAssertEqual(today.duration, sinceMidnight, accuracy: 0.01)
    }

    func testSessionsStartedTodayAddUp() {
        let morning = Record(start: at(0, 6, 0), end: at(0, 8, 0))
        let later = Record(start: at(0, 8, 30), end: at(0, 9, 0))

        let today = Day.today(from: [morning, later], now: at(0, 9, 30))

        XCTAssertEqual(today.records.count, 2)
        XCTAssertEqual(today.duration, 2.5, accuracy: 0.001)
    }

    func testSessionsOutsideTodayAreIgnored() {
        let yesterday = Record(start: at(-1, 8, 0), end: at(-1, 23, 0))
        let tomorrow = Record(start: at(1, 8, 0), end: at(1, 10, 0))

        let today = Day.today(from: [yesterday, tomorrow], now: at(0, 9, 30))

        XCTAssertTrue(today.records.isEmpty)
        XCTAssertEqual(today.duration, 0)
    }

    // MARK: - Day.duration (per-day clipping used by history and stats)

    func testMultiDaySessionIsClippedToEachDay() {
        // 42h session: day -2 at 07:30 -> today at 01:30.
        let session = Record(start: at(-2, 7, 30), end: at(0, 1, 30))

        let firstDay = Day(date: at(-2, 12), records: [session])
        let middleDay = Day(date: at(-1, 12), records: [session])
        let lastDay = Day(date: at(0, 12), records: [session])

        XCTAssertEqual(firstDay.duration, 16.5, accuracy: 0.001)
        XCTAssertEqual(middleDay.duration, 24, accuracy: 0.001)
        XCTAssertEqual(lastDay.duration, 1.5, accuracy: 0.001)
    }

    func testRecordWithoutStartContributesNothing() {
        let day = Day(date: at(0, 12), records: [Record(start: nil, end: nil)])

        XCTAssertEqual(day.duration, 0)
    }

    func testDurationAsProgress() {
        let session = Record(start: at(0, 8, 0), end: at(0, 15, 30))
        let day = Day(date: at(0, 12), records: [session])

        XCTAssertEqual(day.durationAsProgress(goal: 15), 50, accuracy: 0.001)
    }
}
