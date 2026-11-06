import XCTest
@testable import CodexQuotaBar

final class DailyQuotaBudgetTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func remaining(_ used: Double?, at now: Date) -> Int? {
        DailyQuotaBudget.remainingPercent(weeklyUsedPercent: used, resetAt: date(11, hour: 20),
                                          at: now, calendar: calendar)
    }

    func testFirstDayHasOneSeventhAndUnusedBudgetsCarryForward() {
        XCTAssertEqual(remaining(0, at: date(4, hour: 20)), 100)
        XCTAssertEqual(remaining(10, at: date(5, hour: 12)), 130)
        XCTAssertEqual(remaining(30, at: date(6, hour: 12)), 90)
        XCTAssertEqual(remaining(50, at: date(6, hour: 12)), 0)
    }

    func testAllowanceAdvancesAtLocalMidnight() {
        XCTAssertEqual(remaining(0, at: date(4, hour: 23, minute: 59)), 100)
        XCTAssertEqual(remaining(0, at: date(5)), 200)
    }

    func testAtMostSevenBudgetsBeforeReset() {
        XCTAssertEqual(remaining(5, at: date(10, hour: 12)), 665)
        XCTAssertEqual(remaining(5, at: date(11, hour: 19)), 665)
        XCTAssertNil(remaining(5, at: date(11, hour: 20)))
    }

    func testUnknownExpiredAndInvalidValuesDoNotInventADailyBudget() {
        XCTAssertNil(remaining(nil, at: date(6)))
        XCTAssertNil(remaining(.nan, at: date(6)))
        XCTAssertNil(remaining(-1, at: date(6)))
        XCTAssertNil(remaining(10, at: date(4, hour: 19)))
        XCTAssertNil(remaining(10, at: date(12)))
        XCTAssertNil(DailyQuotaBudget.remainingPercent(weeklyUsedPercent: 10, resetAt: nil, at: date(6)))
        XCTAssertEqual(remaining(110, at: date(10)), 0)
    }

    func testDailyColorThresholdsAreStrictAndUnknownIsNeutral() {
        XCTAssertEqual(StatusRowTint.daily(51), .green)
        XCTAssertEqual(StatusRowTint.daily(200), .green)
        XCTAssertEqual(StatusRowTint.daily(50), .normal)
        XCTAssertEqual(StatusRowTint.daily(20), .normal)
        XCTAssertEqual(StatusRowTint.daily(19), .red)
        XCTAssertEqual(StatusRowTint.daily(0), .red)
        XCTAssertEqual(StatusRowTint.daily(nil), .normal)
    }

    func testCodexAndGrokHaveDailyAboveWeeklyWithSameCalculation() {
        let now = date(6, hour: 12)
        let codex = QuotaSnapshot(fiveHourUsedPercent: 5, weeklyUsedPercent: 30, weeklyResetAt: date(11, hour: 20))
        let grok = GrokQuotaSnapshot(usedPercent: 30, resetAt: date(11, hour: 20))
        let codexRows = QuotaStatusPresentation.codexRows(codex, at: now, calendar: calendar)
        let grokRows = QuotaStatusPresentation.grokRows(grok, at: now, calendar: calendar)
        XCTAssertEqual(codexRows, grokRows)
        XCTAssertEqual(codexRows.map(\.badge), ["D", "W"])
        XCTAssertEqual(codexRows.map(\.value), ["90%", "70%"])
        XCTAssertEqual(codexRows.map(\.tint), [.green, .normal])
        XCTAssertTrue(codexRows[0].colorsValue)
        XCTAssertFalse(codexRows[1].colorsValue)
        XCTAssertEqual(codex.displayRows.map(\.badge), ["5H", "W"])
    }

    func testTrialAndHourlyOnlyLimitsDoNotPretendToHaveAWeeklyBudget() {
        let trial = GrokQuotaSnapshot(usedPercent: 25, resetAt: date(11), isTrial: true)
        XCTAssertEqual(QuotaStatusPresentation.grokRows(trial).map(\.badge), ["试用"])
        let hourly = QuotaSnapshot(fiveHourUsedPercent: 5)
        XCTAssertEqual(QuotaStatusPresentation.codexRows(hourly).map(\.badge), ["5H"])
        XCTAssertEqual(QuotaStatusPresentation.codexRows(.empty).map(\.value), ["--", "--"])
        XCTAssertEqual(QuotaStatusPresentation.grokRows(.empty).map(\.value), ["--", "--"])
    }
}
