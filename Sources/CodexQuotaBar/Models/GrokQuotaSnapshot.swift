import Foundation

struct GrokQuotaSnapshot {
    var usedPercent: Double?
    var resetAt: Date?
    var updatedAt: Date?
    var isTrial = false
    var errorMessage: String?

    static let empty = GrokQuotaSnapshot()

    var remainingPercent: Int? {
        usedPercent.map { Int((100 - min(100, max(0, $0))).rounded()) }
    }

    var displayRow: QuotaDisplayRow {
        QuotaDisplayRow(
            badge: isTrial ? "试用" : "W",
            value: remainingPercent.map { "\($0)%" } ?? "--",
            remainingPercent: remainingPercent,
            resetLabel: isTrial ? "试用额度" : "周额度",
            resetValue: resetAt.map { DateFormatter.quotaHour.string(from: $0) } ?? "--"
        )
    }

    var menuTitle: String {
        let title = "Grok \(displayRow.badge) \(displayRow.value)"
        if let errorMessage { return "\(title) · \(errorMessage)" }
        return title + (updatedAt.map { " · 上次刷新于 \(DateFormatter.quotaHour.string(from: $0))" } ?? "")
    }
}
