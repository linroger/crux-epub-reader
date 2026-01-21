import SwiftUI
import SwiftData

struct StreaksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var streaks: [ReadingStreak]
    @Query private var achievements: [Achievement]
    @Query private var sessions: [ReadingSession]
    @Query private var books: [StoredBook]

    private var currentStreak: ReadingStreak? {
        streaks.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Streak section
                    streakSection

                    // Achievements section
                    achievementsSection
                }
                .padding()
            }
            .navigationTitle("Streaks & Achievements")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 600)
        #endif
        .task {
            // Initialize streak if needed
            if streaks.isEmpty {
                let streak = ReadingStreak()
                modelContext.insert(streak)
                try? modelContext.save()
            }

            // Check for new achievements
            if let streak = currentStreak {
                let newAchievements = AchievementChecker.checkAchievements(
                    sessions: sessions,
                    books: books,
                    streak: streak,
                    existingAchievements: achievements,
                    modelContext: modelContext
                )

                if !newAchievements.isEmpty {
                    try? modelContext.save()
                }
            }
        }
    }

    // MARK: - Streak Section

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reading Streak")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let streak = currentStreak {
                VStack(spacing: 20) {
                    // Main streak display
                    HStack(spacing: 40) {
                        // Current streak
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(streak.isStreakActive() ? Color.orange.gradient : Color.gray.gradient)
                                    .frame(width: 120, height: 120)

                                VStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.white)

                                    Text("\(streak.currentStreak)")
                                        .font(.system(size: 36, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)

                                    Text("days")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }

                            Text("Current Streak")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            if !streak.isStreakActive() {
                                Text("Broken")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        Divider()
                            .frame(height: 120)

                        // Best streak
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .stroke(Color.purple.opacity(0.3), lineWidth: 8)
                                    .frame(width: 100, height: 100)

                                VStack(spacing: 2) {
                                    Image(systemName: "trophy.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.purple)

                                    Text("\(streak.longestStreak)")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)

                                    Text("days")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text("Best Streak")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }

                        Divider()
                            .frame(height: 120)

                        // Total days
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 8)
                                    .frame(width: 100, height: 100)

                                VStack(spacing: 2) {
                                    Image(systemName: "calendar.badge.checkmark")
                                        .font(.system(size: 24))
                                        .foregroundStyle(.blue)

                                    Text("\(streak.totalDaysRead)")
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)

                                    Text("days")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text("Total Days")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Streak info
                    VStack(alignment: .leading, spacing: 8) {
                        if streak.isStreakActive() {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Keep it up! Read today to maintain your streak.")
                                    .font(.subheadline)
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                                Text("Start reading today to begin a new streak!")
                                    .font(.subheadline)
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                                .font(.system(size: 12))
                            Text("Streak started: \(streak.streakStartDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Last read: \(streak.lastReadDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Achievements Section

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Achievements")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(achievements.filter { $0.isUnlocked }.count) / \(AchievementType.allCases.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                ForEach(AchievementType.allCases, id: \.rawValue) { type in
                    let achievement = achievements.first { $0.achievementType == type }
                    AchievementBadge(
                        type: type,
                        achievement: achievement
                    )
                }
            }
        }
    }
}

// MARK: - Achievement Badge

struct AchievementBadge: View {
    let type: AchievementType
    let achievement: Achievement?

    private var isUnlocked: Bool {
        achievement?.isUnlocked ?? false
    }

    private var color: Color {
        switch type.color {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "yellow": return .yellow
        case "indigo": return .indigo
        case "cyan": return .cyan
        case "pink": return .pink
        case "teal": return .teal
        default: return .gray
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? color : Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)

                if isUnlocked {
                    Image(systemName: type.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.gray.opacity(0.5))
                }
            }

            VStack(spacing: 4) {
                Text(type.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isUnlocked ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(type.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if isUnlocked, let unlockedAt = achievement?.unlockedAt {
                    Text(unlockedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .frame(minWidth: 150, minHeight: 180)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isUnlocked ? 1.0 : 0.6)
    }
}

#Preview {
    StreaksView()
        .modelContainer(for: [ReadingStreak.self, Achievement.self, ReadingSession.self, StoredBook.self])
}
