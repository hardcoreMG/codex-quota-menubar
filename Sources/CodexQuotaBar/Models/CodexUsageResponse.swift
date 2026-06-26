import Foundation

struct CodexUsageResponse: Decodable {
    let summary: AccountTokenUsageSummary
    let dailyUsageBuckets: [AccountTokenUsageDailyBucket]?
}

struct AccountTokenUsageSummary: Decodable {
    let lifetimeTokens: Int?
    let peakDailyTokens: Int?
    let longestRunningTurnSec: Int?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
}

struct AccountTokenUsageDailyBucket: Decodable {
    let startDate: String
    let tokens: Int
}
