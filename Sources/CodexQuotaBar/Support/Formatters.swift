import Foundation

extension DateFormatter {
    static let bankResetExpiration: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static let quotaHour: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}

/// Shared minute-precision countdown for quota windows and reset credits.
enum QuotaCountdown {
    static func string(until deadline: Date, at now: Date = Date()) -> String {
        let totalMinutes = Int(max(0, deadline.timeIntervalSince(now)) / 60)
        let days = totalMinutes / 1_440
        let hours = totalMinutes % 1_440 / 60
        let minutes = totalMinutes % 60
        return String(format: "%d天 %02d:%02d", days, hours, minutes)
    }
}
