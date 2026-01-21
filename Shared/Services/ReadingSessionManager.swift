import Foundation
import SwiftData

/// Manages reading session tracking
@MainActor
final class ReadingSessionManager {
    private let modelContext: ModelContext
    private var currentSession: ReadingSession?
    private var updateTimer: Timer?
    private var isTrackingEnabled: Bool

    init(modelContext: ModelContext, isTrackingEnabled: Bool = true) {
        self.modelContext = modelContext
        self.isTrackingEnabled = isTrackingEnabled
    }

    /// Start a new reading session
    func startSession(bookId: UUID, chapterIndex: Int) {
        guard isTrackingEnabled else { return }

        // End any existing session first
        endCurrentSession(chapterIndex: chapterIndex)

        // Create new session
        let session = ReadingSession(
            bookId: bookId,
            startedAt: Date(),
            startChapterIndex: chapterIndex
        )
        modelContext.insert(session)
        currentSession = session

        // Start periodic updates (every 30 seconds)
        startUpdateTimer(chapterIndex: chapterIndex)

        try? modelContext.save()
    }

    /// Update the current session with progress
    func updateProgress(chapterIndex: Int) {
        guard isTrackingEnabled, let session = currentSession else { return }

        session.update(chapterIndex: chapterIndex)
        try? modelContext.save()
    }

    /// End the current reading session
    func endCurrentSession(chapterIndex: Int) {
        guard let session = currentSession else { return }

        session.end(chapterIndex: chapterIndex)

        // Update reading streak
        updateReadingStreak(sessionDate: session.startedAt)

        try? modelContext.save()

        currentSession = nil
        stopUpdateTimer()
    }

    /// Pause tracking (e.g., when app goes to background)
    func pauseSession(chapterIndex: Int) {
        guard let session = currentSession else { return }

        session.update(chapterIndex: chapterIndex)
        try? modelContext.save()

        stopUpdateTimer()
    }

    /// Resume tracking (e.g., when app comes to foreground)
    func resumeSession(chapterIndex: Int) {
        guard currentSession != nil else { return }

        startUpdateTimer(chapterIndex: chapterIndex)
    }

    /// Enable or disable tracking
    func setTrackingEnabled(_ enabled: Bool) {
        isTrackingEnabled = enabled

        if !enabled {
            if let session = currentSession {
                session.end(chapterIndex: session.endChapterIndex)
                try? modelContext.save()
            }
            currentSession = nil
            stopUpdateTimer()
        }
    }

    // MARK: - Private Methods

    private func startUpdateTimer(chapterIndex: Int) {
        stopUpdateTimer()

        updateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress(chapterIndex: chapterIndex)
            }
        }
    }

    private func stopUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updateReadingStreak(sessionDate: Date) {
        // Fetch or create reading streak
        let descriptor = FetchDescriptor<ReadingStreak>()
        let streaks = (try? modelContext.fetch(descriptor)) ?? []

        let streak: ReadingStreak
        if let existingStreak = streaks.first {
            streak = existingStreak
        } else {
            streak = ReadingStreak()
            modelContext.insert(streak)
        }

        // Update the streak
        streak.updateStreak(sessionDate: sessionDate)
    }

    // MARK: - Statistics Queries

    /// Get statistics for a specific book
    func getBookStatistics(bookId: UUID) async -> BookReadingStatistics {
        let descriptor = FetchDescriptor<ReadingSession>(
            predicate: #Predicate { $0.bookId == bookId },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )

        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return BookReadingStatistics(sessions: sessions)
    }

    /// Get overall statistics across all books
    func getOverallStatistics(totalBooks: Int, finishedBooks: Int) async -> OverallReadingStatistics {
        let descriptor = FetchDescriptor<ReadingSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )

        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return OverallReadingStatistics(
            sessions: sessions,
            totalBooks: totalBooks,
            finishedBooks: finishedBooks
        )
    }

    /// Get sessions for a specific book
    func getSessions(for bookId: UUID) async -> [ReadingSession] {
        let descriptor = FetchDescriptor<ReadingSession>(
            predicate: #Predicate { $0.bookId == bookId },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Get recent sessions (last 30 days)
    func getRecentSessions(days: Int = 30) async -> [ReadingSession] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let descriptor = FetchDescriptor<ReadingSession>(
            predicate: #Predicate { $0.startedAt >= thirtyDaysAgo },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
