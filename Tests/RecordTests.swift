//
//  RecordTests.swift
//  AndroRingTrackTests
//

import XCTest

final class RecordTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testMatchesTheSampleWithTheSameStart() {
        let starts = [start.addingTimeInterval(-3600), start, start.addingTimeInterval(3600)]

        XCTAssertEqual(Record.sessionMatch(startingAt: start, in: starts), .unique(1))
    }

    func testIgnoresSamplesThatOnlyOverlapTheSession() {
        // A later sample (e.g. a duplicate or a session added in the Health app) must not be
        // picked when closing or editing the session that started earlier.
        let starts = [start.addingTimeInterval(600), start.addingTimeInterval(7200)]

        XCTAssertEqual(Record.sessionMatch(startingAt: start, in: starts), .none)
    }

    func testDoesNotTreatSubSecondDriftAsTheSameSession() {
        let starts = [start.addingTimeInterval(0.0004)]

        XCTAssertEqual(Record.sessionMatch(startingAt: start, in: starts), .none)
    }

    func testFindsExactStartAmongNearbySessions() {
        let starts = [start.addingTimeInterval(0.8), start, start.addingTimeInterval(0.5)]

        XCTAssertEqual(Record.sessionMatch(startingAt: start, in: starts), .unique(1))
    }

    func testNoSamplesMatchesNothing() {
        XCTAssertEqual(Record.sessionMatch(startingAt: start, in: []), .none)
    }

    func testDoesNotMatchAnotherSessionWhenTargetIsMissing() {
        let starts = [start.addingTimeInterval(0.5)]

        XCTAssertEqual(Record.sessionMatch(startingAt: start, in: starts), .none)
    }

    func testDoesNotChooseBetweenSamplesWithTheSameStart() {
        let starts = [start, start]

        XCTAssertEqual(Record.sessionMatch(startingAt: start, in: starts), .ambiguous)
    }
}
