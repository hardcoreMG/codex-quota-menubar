import XCTest
@testable import CodexQuotaBar

final class BankResetTests: XCTestCase {
    func testSortsAvailableCreditsAndExcludesExpiredOrRedeemedCredits() throws {
        let json = #"{"availableCount":3,"credits":[{"id":"no-expiry","status":"available","expiresAt":null},{"id":"later","status":"available","expiresAt":3000},{"id":"earlier","status":"available","expiresAt":2000},{"id":"expired","status":"available","expiresAt":1000},{"id":"used","status":"redeemed","expiresAt":4000}]}"#
        let summary = try JSONDecoder().decode(RateLimitResetCreditsSummary.self, from: Data(json.utf8))
        let credits = summary.availableCredits(at: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(credits.map(\.id), ["earlier", "later", "no-expiry"])
        XCTAssertEqual(credits.last?.expirationValue, "无到期限制")
        XCTAssertEqual(credits.first?.expiresAt, 2000)
    }

    func testSummaryWithoutDetailsRetainsAvailableCount() throws {
        let summary = try JSONDecoder().decode(RateLimitResetCreditsSummary.self, from: Data(#"{"availableCount":5,"credits":null}"#.utf8))
        XCTAssertEqual(summary.availableCount, 5)
        XCTAssertNil(summary.credits)
    }

    func testCountdownAcrossDayAndExpiryBoundaries() {
        let credit = RateLimitResetCredit(id: "test", status: "available", expiresAt: 100_000, title: nil)
        XCTAssertEqual(credit.countdownValue(at: Date(timeIntervalSince1970: 9_939)), "1天 01:01")
        XCTAssertEqual(credit.countdownValue(at: Date(timeIntervalSince1970: 99_999.5)), "0天 00:00")
        XCTAssertEqual(credit.countdownValue(at: Date(timeIntervalSince1970: 100_000)), "已到期")
        XCTAssertEqual(credit.countdownValue(at: Date(timeIntervalSince1970: 100_001)), "已到期")
        XCTAssertEqual(credit.countdownValue(at: Date(timeIntervalSince1970: 99_940)), "0天 00:01")
        let unlimited = RateLimitResetCredit(id: "unlimited", status: "available", expiresAt: nil, title: nil)
        XCTAssertNil(unlimited.countdownValue())
    }

    func testWeeklyCountdownUsesDaysAndClampsAtZero() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(QuotaCountdown.string(until: now.addingTimeInterval(7 * 86400), at: now), "7天 00:00")
        XCTAssertEqual(QuotaCountdown.string(until: now.addingTimeInterval(3660), at: now), "0天 01:01")
        XCTAssertEqual(QuotaCountdown.string(until: now.addingTimeInterval(-60), at: now), "0天 00:00")
    }

    func testOlderResponseWithoutBankResetsStillDecodes() throws {
        let response = try JSONDecoder().decode(CodexRateLimitResponse.self, from: Data(#"{"rateLimits":{"primary":null,"secondary":null}}"#.utf8))
        XCTAssertNil(response.rateLimitResetCredits)
    }
}
