//
//  RecordTests.swift
//  AndroRingTrackTests
//

import XCTest

final class RecordTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testMatchesTheSampleWithTheSameStart() {
        let starts = [start.addingTimeInterval(-3600), start, start.addingTimeInterval(3600)]

        XCTAssertEqual(Record.indexOfSession(startingAt: start, in: starts), 1)
    }

    func testIgnoresSamplesThatOnlyOverlapTheSession() {
        // A later sample (e.g. a duplicate or a session added in the Health app) must not be
        // picked when closing or editing the session that started earlier.
        let starts = [start.addingTimeInterval(600), start.addingTimeInterval(7200)]

        XCTAssertNil(Record.indexOfSession(startingAt: start, in: starts))
    }

    func testToleratesSubSecondDrift() {
        let starts = [start.addingTimeInterval(0.0004)]

        XCTAssertEqual(Record.indexOfSession(startingAt: start, in: starts), 0)
    }

    func testPicksTheClosestStartWithinTolerance() {
        let starts = [start.addingTimeInterval(0.8), start.addingTimeInterval(-0.1), start.addingTimeInterval(0.5)]

        XCTAssertEqual(Record.indexOfSession(startingAt: start, in: starts), 1)
    }

    func testNoSamplesMatchesNothing() {
        XCTAssertNil(Record.indexOfSession(startingAt: start, in: []))
    }
}
