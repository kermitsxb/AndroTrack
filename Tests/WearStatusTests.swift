//
//  WearStatusTests.swift
//  AndroRingTrackTests
//

import XCTest

final class WearStatusTests: XCTestCase {
    private let calendar = Calendar.current
    private var todayStart: Date { calendar.startOfDay(for: Date()) }

    /// Builds a date relative to the start of today: `at(-1, 20, 30)` is yesterday at 20:30.
    private func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(byAdding: .minute, value: dayOffset * 1440 + hour * 60 + minute, to: todayStart)!
    }

    func testNoRecordsIsOffWithFullGoalRemaining() {
        let status = WearStatus(records: [], sessionLength: 15, now: at(0, 10))

        XCTAssertFalse(status.isWorn)
        XCTAssertNil(status.currentSession)
        XCTAssertEqual(status.wornToday, 0, accuracy: 0.001)
        XCTAssertEqual(status.remaining, 15, accuracy: 0.001)
    }

    func testOngoingSessionIsWornWithElapsedTime() {
        let ongoing = Record(start: at(0, 8), end: nil)

        let status = WearStatus(records: [ongoing], sessionLength: 15, now: at(0, 10, 30))

        XCTAssertTrue(status.isWorn)
        XCTAssertTrue(status.currentSession === ongoing)
        XCTAssertEqual(status.currentSessionDuration ?? 0, 2.5, accuracy: 0.001)
    }

    func testWornTodayAddsFinishedAndOngoingSessions() {
        let morning = Record(start: at(0, 6), end: at(0, 9))
        let ongoing = Record(start: at(0, 10), end: nil)

        let status = WearStatus(records: [morning, ongoing], sessionLength: 15, now: at(0, 12))

        XCTAssertEqual(status.wornToday, 5, accuracy: 0.001)
        XCTAssertEqual(status.remaining, 10, accuracy: 0.001)
    }

    func testRemainingNeverGoesNegative() {
        let long = Record(start: at(0, 1), end: at(0, 20))

        let status = WearStatus(records: [long], sessionLength: 15, now: at(0, 21))

        XCTAssertFalse(status.isWorn)
        XCTAssertEqual(status.remaining, 0, accuracy: 0.001)
    }

    func testEstimatedEndOnlyWhileWorn() {
        let ongoing = Record(start: at(0, 8), end: nil)
        let worn = WearStatus(records: [ongoing], sessionLength: 15, now: at(0, 10))
        let off = WearStatus(records: [], sessionLength: 15, now: at(0, 10))

        XCTAssertEqual(worn.estimatedEnd, at(0, 23))
        XCTAssertNil(off.estimatedEnd)
    }

    func testFinishedSessionFromPreviousDayDoesNotCountToday() {
        // Mirrors Day.today: a spillover session that already ended resets the cycle.
        let previous = Record(start: at(-1, 20), end: at(0, 2))

        let status = WearStatus(records: [previous], sessionLength: 15, now: at(0, 10))

        XCTAssertEqual(status.wornToday, 0, accuracy: 0.001)
    }
}
