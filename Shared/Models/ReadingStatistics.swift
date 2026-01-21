import Foundation
import SwiftData

/// Tracks individual reading sessions
@Model
final class ReadingSession {
    @Attribute(.unique) var id: UUID
    var bookId: UUID
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: TimeInterval
    var startChapterIndex: Int
    var endChapterIndex: Int
    var pagesRead: Int

    init(
        id: UUID = UUID(),
        bookId: UUID,
        startedAt: Date = Date(),
        startChapterIndex: Int = 0
    ) {
        self.id = id
        self.bookId = bookId
        self.startedAt = startedAt
        self.endedAt = nil
        self.durationSeconds = 0
        self.startChapterIndex = startChapterIndex
        self.endChapterIndex = startChapterIndex
        self.pagesRead = 0
    }

    /// End the reading session and calculate duration
    func end(at date: Date = Date(), chapterIndex: Int) {
        endedAt = date
        endChapterIndex = chapterIndex
        durationSeconds = date.timeIntervalSince(startedAt)
        pagesRead = max(0, endChapterIndex - startChapterIndex)
    }

    /// Update the session with current progress (called periodically)
    func update(chapterIndex: Int) {
        endChapterIndex = chapterIndex
        if let ended = endedAt {
            durationSeconds = ended.timeIntervalSince(startedAt)
        } else {
            durationSeconds = Date().timeIntervalSince(startedAt)
        }
        pagesRead = max(0, endChapterIndex - startChapterIndex)
    }

    var isActive: Bool {
        endedAt == nil
    }
}

/// Aggregate reading statistics for a book
struct BookReadingStatistics {
    let bookId: UUID
    let totalReadingTime: TimeInterval
    let sessionCount: Int
    let totalPagesRead: Int
    let lastReadAt: Date?
    let firstReadAt: Date?
    let averageSessionDuration: TimeInterval
    let longestSession: TimeInterval
    let currentStreak: Int // days read consecutively

    init(sessions: [ReadingSession]) {
        self.bookId = sessions.first?.bookId ?? UUID()
        self.totalReadingTime = sessions.reduce(0) { $0 + $1.durationSeconds }
        self.sessionCount = sessions.count
        self.totalPagesRead = sessions.reduce(0) { $0 + $1.pagesRead }
        self.lastReadAt = sessions.compactMap { $0.endedAt ?? $0.startedAt }.max()
        self.firstReadAt = sessions.map { $0.startedAt }.min()
        self.averageSessionDuration = sessionCount > 0 ? totalReadingTime / Double(sessionCount) : 0
        self.longestSession = sessions.map { $0.durationSeconds }.max() ?? 0

        // Calculate current streak
        var streak = 0
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Group sessions by day
        let sessionsByDay = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.startedAt)
        }

        // Count consecutive days backwards from today
        var currentDay = today
        while sessionsByDay[currentDay] != nil {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDay) else { break }
            currentDay = previousDay
        }

        self.currentStreak = streak
    }

    /// Formatted total reading time (e.g., "2h 15m")
    var formattedTotalTime: String {
        formatDuration(totalReadingTime)
    }

    /// Formatted average session duration
    var formattedAverageSession: String {
        formatDuration(averageSessionDuration)
    }

    /// Formatted longest session
    var formattedLongestSession: String {
        formatDuration(longestSession)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }
}

/// Overall reading statistics across all books
struct OverallReadingStatistics {
    let totalReadingTime: TimeInterval
    let totalBooks: Int
    let booksFinished: Int
    let totalSessions: Int
    let totalPagesRead: Int
    let currentStreak: Int
    let longestStreak: Int
    let averageSessionDuration: TimeInterval
    let booksThisMonth: Int
    let readingTimeThisMonth: TimeInterval

    init(sessions: [ReadingSession], totalBooks: Int, finishedBooks: Int) {
        self.totalReadingTime = sessions.reduce(0) { $0 + $1.durationSeconds }
        self.totalBooks = totalBooks
        self.booksFinished = finishedBooks
        self.totalSessions = sessions.count
        self.totalPagesRead = sessions.reduce(0) { $0 + $1.pagesRead }
        self.averageSessionDuration = totalSessions > 0 ? totalReadingTime / Double(totalSessions) : 0

        // Calculate current streak
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let sessionsByDay = Dictionary(grouping: sessions) { session in
            calendar.startOfDay(for: session.startedAt)
        }

        var currentStreakDays = 0
        var currentDay = today
        while sessionsByDay[currentDay] != nil {
            currentStreakDays += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDay) else { break }
            currentDay = previousDay
        }
        self.currentStreak = currentStreakDays

        // Calculate longest streak
        let allDays = Array(sessionsByDay.keys).sorted()
        var longestStreakDays = 0
        var tempStreak = 0
        var previousDay: Date?

        for day in allDays {
            if let prev = previousDay,
               let nextDay = calendar.date(byAdding: .day, value: 1, to: prev),
               nextDay == day {
                tempStreak += 1
            } else {
                tempStreak = 1
            }
            longestStreakDays = max(longestStreakDays, tempStreak)
            previousDay = day
        }
        self.longestStreak = longestStreakDays

        // This month stats
        let monthStart = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        let thisMonthSessions = sessions.filter { $0.startedAt >= monthStart }
        self.booksThisMonth = Set(thisMonthSessions.map { $0.bookId }).count
        self.readingTimeThisMonth = thisMonthSessions.reduce(0) { $0 + $1.durationSeconds }
    }

    var formattedTotalTime: String {
        formatDuration(totalReadingTime)
    }

    var formattedAverageSession: String {
        formatDuration(averageSessionDuration)
    }

    var formattedTimeThisMonth: String {
        formatDuration(readingTimeThisMonth)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }
}
