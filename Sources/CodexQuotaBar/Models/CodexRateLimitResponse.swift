import Foundation

struct CodexRateLimitResponse: Decodable {
    let rateLimits: RateLimitSnapshot
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
