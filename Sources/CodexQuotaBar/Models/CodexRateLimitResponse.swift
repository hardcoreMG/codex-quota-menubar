import Foundation

struct CodexRateLimitResponse: Decodable {
    let rateLimits: RateLimitSnapshot
    let rateLimitResetCredits: RateLimitResetCreditsSummary?
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?

    var codexLimit: RateLimitSnapshot {
        rateLimitsByLimitId?["codex"] ?? rateLimits
    }
}

struct RateLimitSnapshot: Decodable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?

    var fiveHourWindow: RateLimitWindow? {
        window(durationMinutes: 5 * 60, legacyFallback: primary)
    }

    var weeklyWindow: RateLimitWindow? {
        window(durationMinutes: 7 * 24 * 60, legacyFallback: secondary)
    }

    private func window(durationMinutes: Int, legacyFallback: RateLimitWindow?) -> RateLimitWindow? {
        let windows = [primary, secondary].compactMap { $0 }

        if let matchingWindow = windows.first(where: { $0.windowDurationMins == durationMinutes }) {
            return matchingWindow
        }

        // Older app-server responses did not always include windowDurationMins.
        return windows.allSatisfy { $0.windowDurationMins == nil } ? legacyFallback : nil
    }
}

struct RateLimitWindow: Decodable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int?
}

struct RateLimitResetCreditsSummary: Decodable {
    let availableCount: Int
    let credits: [RateLimitResetCredit]?

    func availableCredits(at date: Date = Date()) -> [RateLimitResetCredit] {
        (credits ?? []).filter {
            $0.status == "available" && ($0.expiresAt.map { $0 > date.timeIntervalSince1970 } ?? true)
        }.sorted {
            if $0.expiresAt != $1.expiresAt {
                return ($0.expiresAt ?? .infinity) < ($1.expiresAt ?? .infinity)
            }
            return $0.id < $1.id
        }
    }
}

struct RateLimitResetCredit: Decodable {
    let id: String
    let status: String
    let expiresAt: TimeInterval?
    let title: String?

    func countdownValue(at date: Date = Date()) -> String? {
        guard let expiresAt else { return nil }
        let remaining = expiresAt - date.timeIntervalSince1970
        guard remaining > 0 else { return "已到期" }
        return QuotaCountdown.string(until: Date(timeIntervalSince1970: expiresAt), at: date)
    }

    var expirationValue: String {
        expiresAt.map { DateFormatter.bankResetExpiration.string(from: Date(timeIntervalSince1970: $0)) }
            ?? "无到期限制"
    }
}
