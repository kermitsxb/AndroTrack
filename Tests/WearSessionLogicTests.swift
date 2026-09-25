//
//  WearSessionLogicTests.swift
//  AndroRingTrackTests
//

import XCTest

final class WearSessionLogicTests: XCTestCase {
    private let calendar = Calendar.current
    private var todayStart: Date { calendar.startOfDay(for: Date()) }

    /// Builds a date relative to the start of today: `at(-1, 20, 30)` is yesterday at 20:30.
    private func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(byAdding: .minute, value: dayOffset * 1440 + hour * 60 + minute, to: todayStart)!
    }

    // MARK: - openRecord(in:)

    func testOpenRecordIsNilWhenAllRecordsAreClosed() {
        let closed = Record(start: at(0, 1), end: at(0, 5))
        XCTAssertNil(WearSessionLogic.openRecord(in: [closed]))
    }

    func testOpenRecordPicksMostRecentWhenSeveralAreOpen() {
        let older = Record(start: at(-1, 8), end: nil)
        let newer = Record(start: at(0, 8), end: nil)
        XCTAssertTrue(WearSessionLogic.openRecord(in: [newer, older]) === newer)
        XCTAssertTrue(WearSessionLogic.openRecord(in: [older, newer]) === newer)
    }

    // MARK: - startAction

    func testStartActionStartsWhenNoSessionIsOpen() {
        let closed = Record(start: at(0, 1), end: at(0, 5))
        XCTAssertEqual(WearSessionLogic.startAction(records: [closed], now: at(0, 6)), .start)
    }

    func testStartActionDoesNothingWhenSessionIsOpen() {
        let open = Record(start: at(0, 1), end: nil)
        XCTAssertEqual(WearSessionLogic.startAction(records: [open], now: at(0, 6)), WearAction.none)
    }

    // MARK: - stopAction

    func testStopActionDoesNothingWithoutOpenSession() {
        let closed = Record(start: at(0, 1), end: at(0, 5))
        XCTAssertEqual(WearSessionLogic.stopAction(records: [closed], now: at(0, 6)), WearAction.none)
    }

    func testStopActionStoresSessionOfExactlyThreeMinutes() {
        let start = at(0, 8)
        let open = Record(start: start, end: nil)
        let now = start.addingTimeInterval(3 * 60)

        guard case .store(let closed) = WearSessionLogic.stopAction(records: [open], now: now) else {
            return XCTFail("expected .store")
        }
        XCTAssertEqual(closed.id, open.id)
        XCTAssertEqual(closed.start, start)
        XCTAssertEqual(closed.end, now)
    }

    func testStopActionDiscardsSessionUnderThreeMinutes() {
        let start = at(0, 8)
        let open = Record(start: start, end: nil)
        let now = start.addingTimeInterval(3 * 60 - 1)

        XCTAssertEqual(WearSessionLogic.stopAction(records: [open], now: now), .discard(start: start))
    }

    func testStopActionDoesNotMutateTheOpenRecord() {
        let open = Record(start: at(0, 8), end: nil)
        _ = WearSessionLogic.stopAction(records: [open], now: at(0, 12))
        XCTAssertNil(open.end)
    }

    func testStopActionFindsSessionStartedDaysAgo() {
        let open = Record(start: at(-3, 8), end: nil)
        guard case .store(let closed) = WearSessionLogic.stopAction(records: [open], now: at(0, 12)) else {
            return XCTFail("expected .store")
        }
        XCTAssertEqual(closed.start, at(-3, 8))
    }

    // MARK: - toggleAction

    func testToggleStartsWhenNothingIsOpen() {
        XCTAssertEqual(WearSessionLogic.toggleAction(records: [], now: at(0, 6)), .start)
    }

    func testToggleStopsOpenSession() {
        let open = Record(start: at(0, 1), end: nil)
        guard case .store = WearSessionLogic.toggleAction(records: [open], now: at(0, 6)) else {
            return XCTFail("expected .store")
        }
    }

    // MARK: - records(_:applying:now:)

    func testApplyingStartAppendsOpenRecordAtNow() {
        let closed = Record(start: at(0, 1), end: at(0, 5))
        let result = WearSessionLogic.records([closed], applying: .start, now: at(0, 6))

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.last?.start, at(0, 6))
        XCTAssertNil(result.last?.end)
    }

    func testApplyingStoreReplacesOpenRecordById() {
        let other = Record(start: at(0, 1), end: at(0, 2))
        let open = Record(start: at(0, 3), end: nil)
        let closed = Record(id: open.id, start: at(0, 3), end: at(0, 9))

        let result = WearSessionLogic.records([other, open], applying: .store(closed), now: at(0, 9))

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0 === closed })
        XCTAssertFalse(result.contains { $0 === open })
    }

    func testApplyingDiscardRemovesRecordWithThatStart() {
        let other = Record(start: at(0, 1), end: at(0, 2))
        let open = Record(start: at(0, 3), end: nil)

        let result = WearSessionLogic.records([other, open], applying: .discard(start: at(0, 3)), now: at(0, 3, 1))

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first === other)
    }

    // MARK: - outcome(for:records:now:)

    func testOutcomeForStartIsStartedAtNow() {
        XCTAssertEqual(WearSessionLogic.outcome(for: .start, records: [], now: at(0, 6)), .started(at(0, 6)))
    }

    func testOutcomeForNoneWithOpenSessionIsAlreadyStarted() {
        let open = Record(start: at(0, 1), end: nil)
        XCTAssertEqual(WearSessionLogic.outcome(for: .none, records: [open], now: at(0, 6)), .alreadyStarted(at(0, 1)))
    }

    func testOutcomeForNoneWithoutOpenSessionIsNotRunning() {
        XCTAssertEqual(WearSessionLogic.outcome(for: .none, records: [], now: at(0, 6)), .notRunning)
    }

    func testOutcomeForDiscardIsDiscarded() {
        XCTAssertEqual(WearSessionLogic.outcome(for: .discard(start: at(0, 1)), records: [], now: at(0, 6)), .discarded)
    }

    // MARK: - WearStatus.make

    func testStatusWhenOffSumsTodayAndRoundsProgress() {
        // 6h30 worn today, goal 15h → 390 / 900 = 43.3 %
        let closed = Record(start: at(0, 1), end: at(0, 7, 30))

        let status = WearStatus.make(records: [closed], goalHours: 15, now: at(0, 12))

        XCTAssertFalse(status.isWorn)
        XCTAssertNil(status.sessionStart)
        XCTAssertEqual(status.todayMinutes, 390)
        XCTAssertEqual(status.goalHours, 15)
        XCTAssertEqual(status.progressPercent, 43)
    }

    func testStatusExcludesFinishedSessionStartedYesterday() {
        let spillover = Record(start: at(-1, 20), end: at(0, 2))

        let status = WearStatus.make(records: [spillover], goalHours: 15, now: at(0, 12))

        XCTAssertEqual(status.todayMinutes, 0)
        XCTAssertEqual(status.progressPercent, 0)
    }

    func testStatusWhenWornReportsSessionStart() {
        let start = Date().addingTimeInterval(-10 * 60)
        let open = Record(start: start, end: nil)

        let status = WearStatus.make(records: [open], goalHours: 15)

        XCTAssertTrue(status.isWorn)
        XCTAssertEqual(status.sessionStart, start)
    }

    func testStatusClipsOngoingSessionFromYesterdayAtMidnight() {
        let open = Record(start: at(-1, 20), end: nil)

        let status = WearStatus.make(records: [open], goalHours: 15)

        let minutesSinceMidnight = Int((Date().timeIntervalSince(todayStart) / 60).rounded())
        XCTAssertTrue(status.isWorn)
        XCTAssertEqual(status.todayMinutes, minutesSinceMidnight, accuracy: 1)
    }

    func testStatusWithZeroGoalHasZeroProgress() {
        let closed = Record(start: at(0, 1), end: at(0, 2))
        XCTAssertEqual(WearStatus.make(records: [closed], goalHours: 0, now: at(0, 12)).progressPercent, 0)
    }
}
