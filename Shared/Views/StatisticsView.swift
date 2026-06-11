import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var books: [StoredBook]
    @Query private var settings: [AppSettings]

    @State private var overallStats: OverallReadingStatistics?
    @State private var recentSessions: [ReadingSession] = []
    @State private var sessionManager: ReadingSessionManager?
    @State private var selectedTimeRange: TimeRange = .month

    private var isTrackingEnabled: Bool {
        settings.first?.trackReadingTime ?? true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if isTrackingEnabled {
                        if let stats = overallStats {
                            // Overview Cards
                            overviewSection(stats: stats)

                            // Time Range Picker
                            timeRangePicker

                            // Reading Activity Chart
                            activityChartSection

                            // Streak Section
                            streakSection(stats: stats)

                            // Detailed Stats
                            detailedStatsSection(stats: stats)
                        } else {
                            ProgressView("Loading statistics...")
                        }
                    } else {
                        trackingDisabledView
                    }
                }
                .padding()
            }
            .navigationTitle("Reading Statistics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadStatistics()
            }
        }
        #if os(macOS)
        .frame(width: 700, height: 600)
        #endif
    }

    // MARK: - Overview Section

    private func overviewSection(stats: OverallReadingStatistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    title: "Total Reading Time",
                    value: stats.formattedTotalTime,
                    icon: "clock.fill",
                    color: .blue
                )

                StatCard(
                    title: "Books Finished",
                    value: "\(stats.booksFinished)/\(stats.totalBooks)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )

                StatCard(
                    title: "Reading Sessions",
                    value: "\(stats.totalSessions)",
                    icon: "book.fill",
                    color: .purple
                )

                StatCard(
                    title: "Avg. Session",
                    value: stats.formattedAverageSession,
                    icon: "timer",
                    color: .orange
                )
            }
        }
    }

    // MARK: - Time Range Picker

    private var timeRangePicker: some View {
        Picker("Time Range", selection: $selectedTimeRange) {
            ForEach(TimeRange.allCases) { range in
                Text(range.displayName).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedTimeRange) { _, _ in
            loadRecentSessions()
        }
    }

    // MARK: - Activity Chart

    private var activityChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reading Activity")
                .font(.headline)
                .foregroundStyle(.secondary)

            if !recentSessions.isEmpty {
                Chart {
                    ForEach(aggregateByDay(), id: \.date) { data in
                        BarMark(
                            x: .value("Date", data.date, unit: .day),
                            y: .value("Minutes", data.minutes)
                        )
                        .foregroundStyle(.blue.gradient)
                    }
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Int.self) {
                                Text("\(minutes)m")
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Reading Activity",
                    systemImage: "chart.bar",
                    description: Text("Start reading to see your activity")
                )
                .frame(height: 200)
            }
        }
    }

    // MARK: - Streak Section

    private func streakSection(stats: OverallReadingStatistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Streaks")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                StreakCard(
                    title: "Current Streak",
                    days: stats.currentStreak,
                    icon: "flame.fill",
                    color: .orange
                )

                StreakCard(
                    title: "Longest Streak",
                    days: stats.longestStreak,
                    icon: "trophy.fill",
                    color: .yellow
                )
            }
        }
    }

    // MARK: - Detailed Stats

    private func detailedStatsSection(stats: OverallReadingStatistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Month")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                DetailRow(label: "Books Read", value: "\(stats.booksThisMonth)")
                Divider()
                DetailRow(label: "Reading Time", value: stats.formattedTimeThisMonth)
                Divider()
                DetailRow(label: "Pages Read", value: "\(stats.totalPagesRead)")
            }
            .padding()
            .background(Color.cruxControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Tracking Disabled View

    private var trackingDisabledView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Reading Tracking Disabled")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Enable reading time tracking in Settings to see statistics")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Open Settings") {
                #if os(macOS)
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                #endif
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }

    // MARK: - Data Loading

    private func loadStatistics() {
        sessionManager = ReadingSessionManager(
            modelContext: modelContext,
            isTrackingEnabled: isTrackingEnabled
        )

        Task {
            let stats = await sessionManager?.getOverallStatistics(
                totalBooks: books.count,
                finishedBooks: books.filter { $0.isFinished }.count
            )
            overallStats = stats

            loadRecentSessions()
        }
    }

    private func loadRecentSessions() {
        Task {
            let sessions = await sessionManager?.getRecentSessions(days: selectedTimeRange.days) ?? []
            recentSessions = sessions
        }
    }

    // MARK: - Helper Methods

    private func aggregateByDay() -> [(date: Date, minutes: Int)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: recentSessions) { session in
            calendar.startOfDay(for: session.startedAt)
        }

        return grouped.map { date, sessions in
            let totalMinutes = sessions.reduce(0) { $0 + Int($1.durationSeconds / 60) }
            return (date: date, minutes: totalMinutes)
        }.sorted { $0.date < $1.date }
    }
}

// MARK: - Time Range Enum

enum TimeRange: String, CaseIterable, Identifiable {
    case week = "week"
    case month = "month"
    case quarter = "quarter"
    case year = "year"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .quarter: return "3 Months"
        case .year: return "Year"
        }
    }

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding()
        .background(Color.cruxControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct StreakCard: View {
    let title: String
    let days: Int
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(color)

            VStack(spacing: 4) {
                Text("\(days)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(days == 1 ? "day" : "days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.cruxControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    StatisticsView()
        .modelContainer(for: [StoredBook.self, ReadingSession.self, AppSettings.self])
}
