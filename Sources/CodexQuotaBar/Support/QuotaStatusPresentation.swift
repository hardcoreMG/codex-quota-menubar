import Foundation

enum QuotaStatusPresentation {
    static func codexRows(_ snapshot: QuotaSnapshot, at now: Date = Date(), calendar: Calendar = .current) -> [StatusRenderRow] {
        guard let weekly = snapshot.displayRows.first(where: { $0.badge == "W" }) else {
            return snapshot.displayRows.map(quotaRow)
        }
        let daily = DailyQuotaBudget.remainingPercent(weeklyUsedPercent: snapshot.weeklyUsedPercent.map(Double.init),
                                                      resetAt: snapshot.weeklyResetAt, at: now, calendar: calendar)
        return [dailyRow(daily), quotaRow(weekly)]
    }

    static func grokRows(_ snapshot: GrokQuotaSnapshot, at now: Date = Date(), calendar: Calendar = .current) -> [StatusRenderRow] {
        guard !snapshot.isTrial else { return [quotaRow(snapshot.displayRow)] }
        let daily = DailyQuotaBudget.remainingPercent(weeklyUsedPercent: snapshot.usedPercent,
                                                      resetAt: snapshot.resetAt, at: now, calendar: calendar)
        return [dailyRow(daily), quotaRow(snapshot.displayRow)]
    }

    private static func quotaRow(_ row: QuotaDisplayRow) -> StatusRenderRow {
        StatusRenderRow(badge: row.badge, value: row.value,
                        tint: row.remainingPercent.map { $0 <= 20 ? .red : .normal } ?? .normal)
    }

    private static func dailyRow(_ remaining: Int?) -> StatusRenderRow {
        StatusRenderRow(badge: "D", value: remaining.map { "\($0)%" } ?? "--",
                        tint: .daily(remaining), colorsValue: true)
    }
}
