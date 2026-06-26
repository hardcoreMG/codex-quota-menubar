import Foundation

struct QuotaSnapshot {
    var fiveHourUsedPercent: Int?
    var fiveHourResetAt: Date?
    var weeklyUsedPercent: Int?
    var weeklyResetAt: Date?
    var resetCredits: Int?
    var lifetimeTokens: Int?
    var updatedAt: Date?
    var errorMessage: String?

    static let empty = QuotaSnapshot()

    var menuTitle: String {
        "\(menuFiveHourTitle) | \(menuWeeklyTitle)"
    }

    var menuFiveHourTitle: String {
        fiveHourUsedPercent.map { "5h \(100 - $0)%" } ?? "5h --"
    }

    var menuFiveHourValue: String {
        fiveHourUsedPercent.map { "\(100 - $0)%" } ?? "--"
    }

    var fiveHourRemainingPercent: Int? {
        fiveHourUsedPercent.map { 100 - $0 }
    }

    var menuWeeklyTitle: String {
        weeklyUsedPercent.map { "W  \(100 - $0)%" } ?? "W  --"
    }

    var menuWeeklyValue: String {
        weeklyUsedPercent.map { "\(100 - $0)%" } ?? "--"
    }

    var weeklyRemainingPercent: Int? {
        weeklyUsedPercent.map { 100 - $0 }
    }

    var fiveHourLine: String {
        guard let fiveHourUsedPercent else {
            return "5h: unavailable"
        }

        return "5h: \(fiveHourUsedPercent)% used, \(100 - fiveHourUsedPercent)% left"
    }

    var weeklyLine: String {
        guard let weeklyUsedPercent else {
            return "Weekly: unavailable"
        }

        return "Weekly: \(weeklyUsedPercent)% used, \(100 - weeklyUsedPercent)% left"
    }

    var fiveHourResetLine: String {
        "\(fiveHourResetLabel) \(fiveHourResetValue)"
    }

    var fiveHourResetLabel: String {
        "5H 刷新"
    }

    var fiveHourResetValue: String {
        fiveHourResetAt.map { DateFormatter.quotaHour.string(from: $0) } ?? "--"
    }

    var weeklyResetLine: String {
        "\(weeklyResetLabel) \(weeklyResetValue)"
    }

    var weeklyResetLabel: String {
        "W  刷新"
    }

    var weeklyResetValue: String {
        weeklyResetAt.map { DateFormatter.quotaHour.string(from: $0) } ?? "--"
    }

    var updatedLabel: String {
        "上次刷新"
    }

    var updatedValue: String {
        updatedAt.map { DateFormatter.quotaHour.string(from: $0) } ?? "--"
    }

    var updatedLine: String {
        if let errorMessage {
            return "错误：\(errorMessage)"
        }

        return "\(updatedLabel) \(updatedValue)"
    }
}
