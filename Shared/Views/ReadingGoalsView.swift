import SwiftUI
import SwiftData

struct ReadingGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var goals: [ReadingGoal]
    @Query private var achievements: [GoalAchievement]
    @Query private var sessions: [ReadingSession]

    @State private var showingNewGoal = false
    @State private var showingEditGoal: ReadingGoal?

    private var activeGoal: ReadingGoal? {
        goals.first(where: { $0.isActive })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let goal = activeGoal {
                        // Current goal progress
                        currentGoalSection(goal: goal)

                        // Streak and achievements
                        achievementsSection

                        // Goal details
                        goalDetailsSection(goal: goal)
                    } else {
                        // No active goal
                        noGoalSection
                    }

                    // Past achievements
                    if !achievements.isEmpty {
                        pastAchievementsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Reading Goals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if activeGoal != nil {
                            showingEditGoal = activeGoal
                        } else {
                            showingNewGoal = true
                        }
                    } label: {
                        Label(
                            activeGoal == nil ? "New Goal" : "Edit Goal",
                            systemImage: activeGoal == nil ? "plus" : "pencil"
                        )
                    }
                }
            }
            .sheet(isPresented: $showingNewGoal) {
                GoalEditorSheet(goal: nil)
            }
            .sheet(item: $showingEditGoal) { goal in
                GoalEditorSheet(goal: goal)
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }

    // MARK: - Current Goal Section

    private func currentGoalSection(goal: ReadingGoal) -> some View {
        let (periodStart, periodEnd) = goal.getCurrentPeriodDates()
        let currentMinutes = calculateReadingTime(from: periodStart, to: periodEnd)
        let progress = goal.calculateProgress(currentMinutes: currentMinutes)
        let isAchieved = goal.isAchieved(currentMinutes: currentMinutes)

        return VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Goal")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text(goal.period.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Spacer()

                Image(systemName: goal.period.icon)
                    .font(.system(size: 40))
                    .foregroundStyle(isAchieved ? .green : .blue.opacity(0.6))
            }

            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 12)
                    .frame(width: 160, height: 160)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isAchieved ? Color.green.gradient : Color.blue.gradient,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(duration: 0.5), value: progress)

                VStack(spacing: 4) {
                    Text("\(currentMinutes)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("of \(goal.targetMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isAchieved ? .green : .blue)
                }
            }
            .padding(.vertical)

            // Status message
            HStack {
                Image(systemName: isAchieved ? "checkmark.circle.fill" : "clock.fill")
                    .foregroundStyle(isAchieved ? .green : .blue)

                Text(isAchieved ? "Goal achieved! 🎉" : "\(goal.targetMinutes - currentMinutes) minutes to go")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isAchieved ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
            )
        }
        .padding()
        .background(Color.cruxControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Achievements Section

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Month")
                .font(.headline)
                .foregroundStyle(.secondary)

            let monthAchievements = getMonthAchievements()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                AchievementCard(
                    title: "Goals Met",
                    value: "\(monthAchievements.count)",
                    icon: "target",
                    color: .green
                )

                AchievementCard(
                    title: "Total Time",
                    value: formatMinutes(getTotalMonthMinutes()),
                    icon: "clock.fill",
                    color: .blue
                )
            }
        }
    }

    // MARK: - Goal Details Section

    private func goalDetailsSection(goal: ReadingGoal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Goal Details")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                DetailRow(label: "Period", value: goal.period.displayName)
                Divider()
                DetailRow(label: "Target", value: "\(goal.targetMinutes) minutes")
                Divider()
                DetailRow(label: "Created", value: goal.createdAt.formatted(date: .abbreviated, time: .omitted))
            }
            .padding()
            .background(Color.cruxControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - No Goal Section

    private var noGoalSection: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "target")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Active Goal")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Set a reading goal to track your progress and build a reading habit")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                showingNewGoal = true
            } label: {
                Label("Create Goal", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    // MARK: - Past Achievements Section

    private var pastAchievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Achievements")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(achievements.prefix(5)) { achievement in
                    HStack {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(.yellow)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(GoalPeriod(rawValue: achievement.goalType)?.displayName ?? "Goal")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("\(achievement.actualMinutes) of \(achievement.targetMinutes) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(achievement.achievedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)

                    if achievement.id != achievements.prefix(5).last?.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color.cruxControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Helper Methods

    private func calculateReadingTime(from start: Date, to end: Date) -> Int {
        let periodSessions = sessions.filter { session in
            session.startedAt >= start && session.startedAt < end
        }

        return periodSessions.reduce(0) { total, session in
            total + Int(session.durationSeconds / 60)
        }
    }

    private func getMonthAchievements() -> [GoalAchievement] {
        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now

        return achievements.filter { $0.achievedAt >= monthStart }
    }

    private func getTotalMonthMinutes() -> Int {
        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now

        return getMonthAchievements().reduce(0) { $0 + $1.actualMinutes }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
}

// MARK: - Goal Editor Sheet

struct GoalEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var existingGoals: [ReadingGoal]

    let goal: ReadingGoal?

    @State private var selectedPeriod: GoalPeriod
    @State private var targetMinutes: Int

    init(goal: ReadingGoal?) {
        self.goal = goal
        _selectedPeriod = State(initialValue: goal?.period ?? .weekly)
        _targetMinutes = State(initialValue: goal?.targetMinutes ?? GoalPeriod.weekly.defaultTargetMinutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(GoalPeriod.allCases) { period in
                            Label(period.displayName, systemImage: period.icon)
                                .tag(period)
                        }
                    }
                    .onChange(of: selectedPeriod) { _, newPeriod in
                        // Update target to default for selected period if it's a new goal
                        if goal == nil {
                            targetMinutes = newPeriod.defaultTargetMinutes
                        }
                    }
                } header: {
                    Text("Goal Period")
                } footer: {
                    Text("Choose how often you want to achieve your reading goal")
                }

                Section {
                    Stepper("\(targetMinutes) minutes", value: $targetMinutes, in: 10...10000, step: 10)

                    Text(formatTargetDescription())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Target")
                } footer: {
                    Text("Set a realistic target that fits your schedule")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                            Text("Recommended Targets")
                                .fontWeight(.medium)
                        }
                        .font(.system(size: 13))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Daily: 20-30 minutes")
                            Text("• Weekly: 2-3 hours (120-180 min)")
                            Text("• Monthly: 8-12 hours (480-720 min)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(goal == nil ? "New Goal" : "Edit Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(goal == nil ? "Create" : "Save") {
                        saveGoal()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }

    private func formatTargetDescription() -> String {
        let hours = targetMinutes / 60
        let mins = targetMinutes % 60

        var description = ""
        if hours > 0 {
            description = "\(hours) hour\(hours == 1 ? "" : "s")"
            if mins > 0 {
                description += " and \(mins) minute\(mins == 1 ? "" : "s")"
            }
        } else {
            description = "\(mins) minute\(mins == 1 ? "" : "s")"
        }

        return description + " per \(selectedPeriod.displayName.lowercased())"
    }

    private func saveGoal() {
        if let existingGoal = goal {
            // Edit existing goal
            existingGoal.period = selectedPeriod
            existingGoal.targetMinutes = targetMinutes
        } else {
            // Deactivate all existing goals
            for existingGoal in existingGoals {
                existingGoal.isActive = false
            }

            // Create new goal
            let newGoal = ReadingGoal(
                period: selectedPeriod,
                targetMinutes: targetMinutes
            )
            modelContext.insert(newGoal)
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Supporting Views

struct AchievementCard: View {
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

#Preview {
    ReadingGoalsView()
        .modelContainer(for: [ReadingGoal.self, GoalAchievement.self, ReadingSession.self])
}
