import Foundation
import SwiftData

/// Reading goal model for tracking user reading targets
@Model
final class ReadingGoal {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var goalType: String  // "daily", "weekly", "monthly", "yearly"
    var targetMinutes: Int  // Target reading time in minutes
    var startDate: Date
    var endDate: Date?  // Optional end date for custom goals
    var isActive: Bool  // Whether this goal is currently active

    // Computed property for goal period
    var period: GoalPeriod {
        get { GoalPeriod(rawValue: goalType) ?? .weekly }
        set { goalType = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        period: GoalPeriod = .weekly,
        targetMinutes: Int = 150,  // Default: 150 minutes per week
        startDate: Date = Date(),
        endDate: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.createdAt = createdAt
        self.goalType = period.rawValue
        self.targetMinutes = targetMinutes
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
    }

    /// Get the current period's start and end dates
    func getCurrentPeriodDates() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()

        switch period {
        case .daily:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)

        case .weekly:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            return (start, end)

        case .monthly:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let end = calendar.date(byAdding: .month, value: 1, to: start)!
            return (start, end)

        case .yearly:
            let start = calendar.dateInterval(of: .year, for: now)?.start ?? now
            let end = calendar.date(byAdding: .year, value: 1, to: start)!
            return (start, end)
        }
    }

    /// Calculate progress percentage for current period
    func calculateProgress(currentMinutes: Int) -> Double {
        guard targetMinutes > 0 else { return 0 }
        return min(Double(currentMinutes) / Double(targetMinutes), 1.0)
    }

    /// Check if goal is achieved for current period
    func isAchieved(currentMinutes: Int) -> Bool {
        return currentMinutes >= targetMinutes
    }
}

// MARK: - Goal Period Enum

enum GoalPeriod: String, CaseIterable, Identifiable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case yearly = "yearly"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    var defaultTargetMinutes: Int {
        switch self {
        case .daily: return 30    // 30 minutes per day
        case .weekly: return 150   // 2.5 hours per week
        case .monthly: return 600  // 10 hours per month
        case .yearly: return 7200  // 120 hours per year
        }
    }

    var icon: String {
        switch self {
        case .daily: return "sun.max.fill"
        case .weekly: return "calendar"
        case .monthly: return "calendar.badge.clock"
        case .yearly: return "calendar.circle.fill"
        }
    }
}

// MARK: - Goal Achievement Record

@Model
final class GoalAchievement {
    @Attribute(.unique) var id: UUID
    var achievedAt: Date
    var goalId: UUID
    var goalType: String
    var targetMinutes: Int
    var actualMinutes: Int
    var periodStartDate: Date
    var periodEndDate: Date

    init(
        id: UUID = UUID(),
        achievedAt: Date = Date(),
        goalId: UUID,
        goalType: String,
        targetMinutes: Int,
        actualMinutes: Int,
        periodStartDate: Date,
        periodEndDate: Date
    ) {
        self.id = id
        self.achievedAt = achievedAt
        self.goalId = goalId
        self.targetMinutes = targetMinutes
        self.actualMinutes = actualMinutes
        self.periodStartDate = periodStartDate
        self.periodEndDate = periodEndDate
        self.goalType = goalType
    }
}
