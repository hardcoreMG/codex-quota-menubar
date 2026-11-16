import XCTest
@testable import CodexQuotaBar

final class GrokQuotaCacheTests: XCTestCase {
    private var root: URL!
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let accountKey = "sand.client.slice.client-meta.account-slot"
    private let cacheKey = "sand.client.slice.account.test%7Caccount.weekly-usage.cache"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sand-client-persistence"),
                                                withIntermediateDirectories: true)
        try write(accountKey, object: ["schemaVersion": 1, "value": "test|account"])
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testReadsActiveAccountPercentageAndMillisecondDates() throws {
        try write(cacheKey, object: cache(percent: 1.018418201516793))
        let snapshot = try GrokQuotaCacheClient(userDataURL: root).readQuota(at: now)
        XCTAssertEqual(snapshot.remainingPercent, 99)
        XCTAssertEqual(snapshot.resetAt, now.addingTimeInterval(3600))
        XCTAssertEqual(snapshot.updatedAt, now.addingTimeInterval(-60))
        XCTAssertEqual(snapshot.displayRow.badge, "W")
    }

    func testReadsSchema3QuotaWithAdditionalPlanFields() throws {
        var fixture = cache(percent: 7.497291440953413)
        fixture["schemaVersion"] = 3
        var value = fixture["value"] as! [String: Any]
        var reading = value["reading"] as! [String: Any]
        var usage = reading["usage"] as! [String: Any]
        usage.merge(["hasNonZeroIncludedLimit": true, "isTeamSeat": false,
                     "onDemand": NSNull(), "prepaidBalanceCents": 0,
                     "grokPlanLabel": "Grok Bot Plan", "readForTeamId": NSNull()]) { _, new in new }
        reading["usage"] = usage
        value["reading"] = reading
        fixture["value"] = value
        try write(cacheKey, object: fixture)

        let snapshot = try GrokQuotaCacheClient(userDataURL: root).readQuota(at: now)
        XCTAssertEqual(snapshot.remainingPercent, 93)
        XCTAssertEqual(snapshot.resetAt, now.addingTimeInterval(3600))
        XCTAssertEqual(snapshot.updatedAt, now.addingTimeInterval(-60))
        XCTAssertFalse(snapshot.isTrial)
    }

    func testDoesNotUseAnotherAccountsCache() throws {
        try write(cacheKey, object: cache())
        try write(accountKey, object: ["schemaVersion": 1, "value": "other"])
        XCTAssertThrowsError(try GrokQuotaCacheClient(userDataURL: root).readQuota(at: now)) { error in
            guard case GrokQuotaCacheError.unavailable = error else { return XCTFail("\(error)") }
        }
    }

    func testSignedOutAccountDoesNotDisplayCachedQuota() throws {
        try write(cacheKey, object: cache())
        try Data(#"{"signedIn":false}"#.utf8).write(to: root.appendingPathComponent("desktop-status.json"))
        XCTAssertThrowsError(try GrokQuotaCacheClient(userDataURL: root).readQuota(at: now)) { error in
            guard case GrokQuotaCacheError.signedOut = error else { return XCTFail("\(error)") }
        }
    }

    func testRejectsExpiredCacheAtResetAndMaximumAgeBoundaries() throws {
        for fixture in [cache(expiresAfter: 0), cache(resetAfter: 0), cache(readAgo: 86_400)] {
            try write(cacheKey, object: fixture)
            XCTAssertThrowsError(try GrokQuotaCacheClient(userDataURL: root).readQuota(at: now)) { error in
                guard case GrokQuotaCacheError.expired = error else { return XCTFail("\(error)") }
            }
        }
    }

    func testAbsentAndUnknownSchemaAreNotShownAsZeroUsage() throws {
        try write(cacheKey, object: ["schemaVersion": 2, "value": ["kind": "absent", "expiresAtMs": 1_001_000_000]])
        XCTAssertThrowsError(try GrokQuotaCacheClient(userDataURL: root).readQuota(at: now))
        var fixture = cache()
        fixture["schemaVersion"] = 4
        try write(cacheKey, object: fixture)
        XCTAssertThrowsError(try GrokQuotaCacheClient(userDataURL: root).readQuota(at: now))
    }

    func testOverLimitClampsToZeroAndUnknownIsDistinct() throws {
        try write(cacheKey, object: cache(percent: 120))
        let snapshot = try GrokQuotaCacheClient(userDataURL: root).readQuota(at: now)
        XCTAssertEqual(snapshot.remainingPercent, 0)
        XCTAssertEqual(snapshot.displayRow.value, "0%")
        XCTAssertNil(GrokQuotaSnapshot.empty.remainingPercent)
        XCTAssertEqual(GrokQuotaSnapshot.empty.displayRow.value, "--")
    }

    func testTrialAndMissingReset() throws {
        var fixture = cache()
        var value = fixture["value"] as! [String: Any]
        var reading = value["reading"] as! [String: Any]
        var usage = reading["usage"] as! [String: Any]
        usage["isSandTrial"] = true
        usage["nextResetMs"] = NSNull()
        reading["usage"] = usage
        value["reading"] = reading
        fixture["value"] = value
        try write(cacheKey, object: fixture)
        let snapshot = try GrokQuotaCacheClient(userDataURL: root).readQuota(at: now)
        XCTAssertEqual(snapshot.displayRow.badge, "试用")
        XCTAssertEqual(snapshot.displayRow.resetValue, "--")
    }

    func testKnownBase32FilenameAndDigestFramedLongAccountKey() throws {
        XCTAssertEqual(GrokQuotaCacheClient.blobName(for: accountKey),
                       "onqw4zbomnwgszlooqxhg3djmnss4y3mnfsw45bnnvsxiyjomfrwg33vnz2c243mn52a.blob")
        let account = String(repeating: "a", count: 200)
        let key = "sand.client.slice.account.\(account).weekly-usage.cache"
        XCTAssertTrue(GrokQuotaCacheClient.blobName(for: key).hasSuffix(".kblob"))
        try write(accountKey, object: ["schemaVersion": 1, "value": account])
        try write(key, object: cache())
        XCTAssertEqual(try GrokQuotaCacheClient(userDataURL: root).readQuota(at: now).remainingPercent, 75)
    }

    private func cache(percent: Double = 25, expiresAfter: Double = 7200,
                       resetAfter: Double = 3600, readAgo: Double = 60) -> [String: Any] {
        ["schemaVersion": 2, "value": [
            "kind": "present", "selectedTeamId": NSNull(),
            "reading": ["usage": ["percentUsed": percent,
                                   "nextResetMs": now.addingTimeInterval(resetAfter).timeIntervalSince1970 * 1000,
                                   "isSandTrial": false, "unifiedPlanName": "Premium"],
                        "readAtMs": now.addingTimeInterval(-readAgo).timeIntervalSince1970 * 1000],
            "expiresAtMs": now.addingTimeInterval(expiresAfter).timeIntervalSince1970 * 1000
        ]]
    }

    private func write(_ key: String, object: [String: Any]) throws {
        let name = GrokQuotaCacheClient.blobName(for: key)
        var data = Data()
        if name.hasSuffix(".kblob") {
            data = try JSONEncoder().encode(key)
            data.append(0x0A)
        }
        data.append(try JSONSerialization.data(withJSONObject: object))
        try data.write(to: root.appendingPathComponent("sand-client-persistence").appendingPathComponent(name))
    }
}
