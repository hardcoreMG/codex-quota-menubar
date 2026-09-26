import Foundation

struct QuotaDisplayRow: Equatable {
    let badge: String
    let value: String
    let remainingPercent: Int?
    let resetLabel: String
    let resetValue: String
}

struct QuotaSnapshot {
    var fiveHourUsedPercent: Int?
    var fiveHourResetAt: Date?
    var weeklyUsedPercent: Int?
    var weeklyResetAt: Date?
    var bankResets: RateLimitResetCreditsSummary?
    var errorMessage: String?

    static let empty = QuotaSnapshot()

    var displayRows: [QuotaDisplayRow] {
        var rows: [QuotaDisplayRow] = []

        if fiveHourUsedPercent != nil || fiveHourResetAt != nil {
            rows.append(QuotaDisplayRow(
                badge: "5H",
                value: menuFiveHourValue,
                remainingPercent: fiveHourRemainingPercent,
                resetLabel: fiveHourResetLabel,
                resetValue: fiveHourResetValue
            ))
        }

        if weeklyUsedPercent != nil || weeklyResetAt != nil {
            rows.append(QuotaDisplayRow(
                badge: "W",
                value: menuWeeklyValue,
                remainingPercent: weeklyRemainingPercent,
                resetLabel: weeklyResetLabel,
                resetValue: weeklyResetValue
            ))
        }

        if rows.isEmpty {
            return [
                QuotaDisplayRow(badge: "5H", value: "--", remainingPercent: nil, resetLabel: fiveHourResetLabel, resetValue: "--"),
                QuotaDisplayRow(badge: "W", value: "--", remainingPercent: nil, resetLabel: weeklyResetLabel, resetValue: "--")
            ]
        }

        return rows
    }

    var menuTitle: String {
        displayRows.map { "\($0.badge) \($0.value)" }.joined(separator: " | ")
    }

    var menuFiveHourValue: String {
        fiveHourUsedPercent.map { "\(100 - $0)%" } ?? "--"
    }

    var fiveHourRemainingPercent: Int? {
        fiveHourUsedPercent.map { 100 - $0 }
    }

    var menuWeeklyValue: String {
        weeklyUsedPercent.map { "\(100 - $0)%" } ?? "--"
    }

    var weeklyRemainingPercent: Int? {
        weeklyUsedPercent.map { 100 - $0 }
    }

    var fiveHourResetLabel: String {
        "5H 刷新"
    }

    var fiveHourResetValue: String {
        fiveHourResetAt.map { DateFormatter.quotaHour.string(from: $0) } ?? "--"
    }

    var weeklyResetLabel: String {
        "周额度"
    }

    var weeklyResetValue: String {
        weeklyResetAt.map { DateFormatter.quotaHour.string(from: $0) } ?? "--"
    }

}
