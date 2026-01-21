import Foundation
import SwiftData

/// Model for tracking reading streaks
@Model
final class ReadingStreak {
    @Attribute(.unique) var id: UUID
    var currentStreak: Int  // Current consecutive days with reading
    var longestStreak: Int  // Longest streak ever achieved
    var lastReadDate: Date  // Last date user read
    var streakStartDate: Date  // When current streak started
    var totalDaysRead: Int  // Total number of days with reading activity

    init(
        id: UUID = UUID(),
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        lastReadDate: Date = Date(),
        streakStartDate: Date = Date(),
        totalDaysRead: Int = 0
    ) {
        self.id = id
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastReadDate = lastReadDate
        self.streakStartDate = streakStartDate
        self.totalDaysRead = totalDaysRead
    }

    /// Update streak based on a new reading session
    func updateStreak(sessionDate: Date) {
        let calendar = Calendar.current
        let sessionDay = calendar.startOfDay(for: sessionDate)
        let lastDay = calendar.startOfDay(for: lastReadDate)

        // If same day, no change needed
        if sessionDay == lastDay {
            return
        }

        // Check if session is next day (continuing streak)
        if let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDay),
           sessionDay == nextDay {
            currentStreak += 1
            if currentStreak > longestStreak {
                longestStreak = currentStreak
            }
        }
        // Check if session breaks the streak (more than 1 day gap)
        else if sessionDay > lastDay {
            // Streak broken, restart
            currentStreak = 1
            streakStartDate = sessionDay
        }

        lastReadDate = sessionDate
        totalDaysRead += 1
    }

    /// Check if streak is still active (read today or yesterday)
    func isStreakActive() -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastDay = calendar.startOfDay(for: lastReadDate)

        // Active if read today
        if lastDay == today {
            return true
        }

        // Active if read yesterday (grace period)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           lastDay == yesterday {
            return true
        }

        return false
    }
}

// MARK: - Reading Achievements

enum AchievementType: String, CaseIterable, Codable {
    // Reading duration achievements
    case firstBook = "first_book"
    case tenBooks = "ten_books"
    case fiftyBooks = "fifty_books"
    case hundredBooks = "hundred_books"

    // Time-based achievements
    case oneHourDay = "one_hour_day"
    case fiveHoursWeek = "five_hours_week"
    case marathonReader = "marathon_reader"  // 10+ hours in a week

    // Streak achievements
    case weekStreak = "week_streak"
    case monthStreak = "month_streak"
    case hundredDayStreak = "hundred_day_streak"
    case yearStreak = "year_streak"

    // Consistency achievements
    case earlyBird = "early_bird"  // Reading before 8am
    case nightOwl = "night_owl"  // Reading after 10pm
    case weekendWarrior = "weekend_warrior"  // Reading on weekends

    // Milestone achievements
    case thousandPages = "thousand_pages"
    case tenThousandPages = "ten_thousand_pages"
    case hundredHours = "hundred_hours"
    case thousandHours = "thousand_hours"

    var title: String {
        switch self {
        case .firstBook: return "First Steps"
        case .tenBooks: return "Avid Reader"
        case .fiftyBooks: return "Bookworm"
        case .hundredBooks: return "Literary Master"
        case .oneHourDay: return "Dedicated Reader"
        case .fiveHoursWeek: return "Weekly Champion"
        case .marathonReader: return "Marathon Reader"
        case .weekStreak: return "Week Warrior"
        case .monthStreak: return "Monthly Master"
        case .hundredDayStreak: return "Century of Reading"
        case .yearStreak: return "Yearly Legend"
        case .earlyBird: return "Early Bird"
        case .nightOwl: return "Night Owl"
        case .weekendWarrior: return "Weekend Warrior"
        case .thousandPages: return "Page Turner"
        case .tenThousandPages: return "Epic Reader"
        case .hundredHours: return "Time Traveler"
        case .thousandHours: return "Master of Time"
        }
    }

    var description: String {
        switch self {
        case .firstBook: return "Completed your first book"
        case .tenBooks: return "Read 10 books"
        case .fiftyBooks: return "Read 50 books"
        case .hundredBooks: return "Read 100 books"
        case .oneHourDay: return "Read for 1 hour in a single day"
        case .fiveHoursWeek: return "Read for 5 hours in a week"
        case .marathonReader: return "Read for 10+ hours in a week"
        case .weekStreak: return "Read for 7 consecutive days"
        case .monthStreak: return "Read for 30 consecutive days"
        case .hundredDayStreak: return "Read for 100 consecutive days"
        case .yearStreak: return "Read for 365 consecutive days"
        case .earlyBird: return "Read before 8am"
        case .nightOwl: return "Read after 10pm"
        case .weekendWarrior: return "Read on a weekend"
        case .thousandPages: return "Read 1,000 pages"
        case .tenThousandPages: return "Read 10,000 pages"
        case .hundredHours: return "Read for 100 hours total"
        case .thousandHours: return "Read for 1,000 hours total"
        }
    }

    var icon: String {
        switch self {
        case .firstBook: return "book.fill"
        case .tenBooks, .fiftyBooks, .hundredBooks: return "books.vertical.fill"
        case .oneHourDay, .fiveHoursWeek, .marathonReader: return "clock.fill"
        case .weekStreak, .monthStreak, .hundredDayStreak, .yearStreak: return "flame.fill"
        case .earlyBird: return "sunrise.fill"
        case .nightOwl: return "moon.stars.fill"
        case .weekendWarrior: return "calendar.badge.clock"
        case .thousandPages, .tenThousandPages: return "doc.text.fill"
        case .hundredHours, .thousandHours: return "hourglass"
        }
    }

    var color: String {
        switch self {
        case .firstBook, .tenBooks: return "blue"
        case .fiftyBooks, .hundredBooks: return "purple"
        case .oneHourDay, .fiveHoursWeek, .marathonReader: return "green"
        case .weekStreak, .monthStreak: return "orange"
        case .hundredDayStreak, .yearStreak: return "red"
        case .earlyBird: return "yellow"
        case .nightOwl: return "indigo"
        case .weekendWarrior: return "cyan"
        case .thousandPages, .tenThousandPages: return "pink"
        case .hundredHours, .thousandHours: return "teal"
        }
    }
}

@Model
final class Achievement {
    @Attribute(.unique) var id: UUID
    var type: String  // AchievementType rawValue
    var unlockedAt: Date
    var progress: Double  // 0.0 to 1.0 for tracking partial progress
    var isUnlocked: Bool

    // Computed property for achievement type
    var achievementType: AchievementType? {
        AchievementType(rawValue: type)
    }

    init(
        id: UUID = UUID(),
        type: AchievementType,
        unlockedAt: Date = Date(),
        progress: Double = 0.0,
        isUnlocked: Bool = false
    ) {
        self.id = id
        self.type = type.rawValue
        self.unlockedAt = unlockedAt
        self.progress = progress
        self.isUnlocked = isUnlocked
    }
}

// MARK: - Achievement Checker

class AchievementChecker {
    /// Check and update achievements based on current reading data
    static func checkAchievements(
        sessions: [ReadingSession],
        books: [StoredBook],
        streak: ReadingStreak,
        existingAchievements: [Achievement],
        modelContext: ModelContext
    ) -> [Achievement] {
        var newAchievements: [Achievement] = []
        let existingTypes = Set(existingAchievements.compactMap { $0.achievementType })

        // Book count achievements
        let completedBooks = books.filter { $0.readingStatus == .finished }.count
        checkAndUnlock(.firstBook, count: completedBooks, threshold: 1, existingTypes: existingTypes, newAchievements: &newAchievements, modelContext: modelContext)
        checkAndUnlock(.tenBooks, count: completedBooks, threshold: 10, existingTypes: existingTypes, newAchievements: &newAchievements, modelContext: modelContext)
        checkAndUnlock(.fiftyBooks, count: completedBooks, threshold: 50, existingTypes: existingTypes, newAchievements: &newAchievements, modelContext: modelContext)
        checkAndUnlock(.hundredBooks, count: completedBooks, threshold: 100, existingTypes: existingTypes, newAchievements: &newAchievements, modelContext: modelContext)

        // Time-based achievements
        let totalHours = sessions.reduce(0.0) { $0 + $1.durationSeconds / 3600.0 }
        checkAndUnlock(.hundredHours, count: Int(totalHours), threshold: 100, existingTypes: existingTypes, newAchievements: &newAchievements, modelContext: modelContext)
        checkAndUnlock(.thousandHours, count: Int(totalHours), threshold: 1000, existingTypes: existingTypes, newAchievements: &newAchievements, modelContext: modelContext)

        // Streak achievements
        checkAndUnlock(.weekStreak, count: streak.currentStreak, threshold: 7, existingTypes: existingTypes, newAchievements: &newAchievements, modelContext: modelContext)
        checkAndUnlock(.monthStreak, count: streak.currentStreak, threshold: 30, existingTypes: existingTypes, newAchievements: &newAchievements, modelContext: modelContext)
        checkAndUnlock(.hundredDayStreak, count: streak.currentStreak, threshold: 100, existingTypes: existingTypes, newAchievements: &newAchievements, modelContext: modelContext)
        checkAndUnlock(.yearStreak, count: streak.currentStreak, threshold: 365, existingTypes: existingTypes, newAchievements: &newAchievements, modelContext: modelContext)

        // Daily achievements
        let calendar = Calendar.current
        for session in sessions {
            let hour = calendar.component(.hour, from: session.startedAt)

            // Early bird (before 8am)
            if hour < 8 && !existingTypes.contains(.earlyBird) {
                let achievement = Achievement(type: .earlyBird, unlockedAt: session.startedAt, isUnlocked: true)
                modelContext.insert(achievement)
                newAchievements.append(achievement)
            }

            // Night owl (after 10pm)
            if hour >= 22 && !existingTypes.contains(.nightOwl) {
                let achievement = Achievement(type: .nightOwl, unlockedAt: session.startedAt, isUnlocked: true)
                modelContext.insert(achievement)
                newAchievements.append(achievement)
            }

            // Weekend warrior
            let weekday = calendar.component(.weekday, from: session.startedAt)
            if (weekday == 1 || weekday == 7) && !existingTypes.contains(.weekendWarrior) {
                let achievement = Achievement(type: .weekendWarrior, unlockedAt: session.startedAt, isUnlocked: true)
                modelContext.insert(achievement)
                newAchievements.append(achievement)
            }
        }

        return newAchievements
    }

    private static func checkAndUnlock(
        _ type: AchievementType,
        count: Int,
        threshold: Int,
        existingTypes: Set<AchievementType>,
        newAchievements: inout [Achievement],
        modelContext: ModelContext
    ) {
        if count >= threshold && !existingTypes.contains(type) {
            let achievement = Achievement(
                type: type,
                unlockedAt: Date(),
                progress: 1.0,
                isUnlocked: true
            )
            modelContext.insert(achievement)
            newAchievements.append(achievement)
        }
    }
}
