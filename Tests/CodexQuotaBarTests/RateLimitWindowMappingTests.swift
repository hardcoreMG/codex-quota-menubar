import XCTest
@testable import CodexQuotaBar

final class RateLimitWindowMappingTests: XCTestCase {
    func testProPrimaryWeeklyWindowIsNotTreatedAsFiveHourWindow() throws {
        let snapshot = try decodeRateLimitSnapshot(
            primaryDuration: 10_080,
            secondaryDuration: nil
        )

        XCTAssertNil(snapshot.fiveHourWindow)
        XCTAssertEqual(snapshot.weeklyWindow?.windowDurationMins, 10_080)
    }

    func testPlusWindowsAreMappedByDuration() throws {
        let snapshot = try decodeRateLimitSnapshot(
            primaryDuration: 300,
            secondaryDuration: 10_080
        )

        XCTAssertEqual(snapshot.fiveHourWindow?.windowDurationMins, 300)
        XCTAssertEqual(snapshot.weeklyWindow?.windowDurationMins, 10_080)
    }

    func testProSnapshotDisplaysOnlyWeeklyQuota() {
        let snapshot = QuotaSnapshot(weeklyUsedPercent: 3)

        XCTAssertEqual(snapshot.displayRows.map(\.badge), ["W"])
        XCTAssertEqual(snapshot.displayRows.map(\.value), ["97%"])
    }

    private func decodeRateLimitSnapshot(
        primaryDuration: Int?,
        secondaryDuration: Int?
    ) throws -> RateLimitSnapshot {
        let primary = windowJSON(duration: primaryDuration)
        let secondary = secondaryDuration.map { windowJSON(duration: $0) } ?? "null"
        let json = """
        {
          "primary": \(primary),
          "secondary": \(secondary)
        }
        """

        return try JSONDecoder().decode(RateLimitSnapshot.self, from: Data(json.utf8))
    }

    private func windowJSON(duration: Int?) -> String {
        let durationValue = duration.map(String.init) ?? "null"
        return """
        {
          "usedPercent": 3,
          "windowDurationMins": \(durationValue),
          "resetsAt": 1789290708
        }
        """
    }
}
