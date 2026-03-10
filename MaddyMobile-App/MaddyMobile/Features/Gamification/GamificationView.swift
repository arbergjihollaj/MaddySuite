import SwiftUI

/// File: Features/Gamification/GamificationView.swift

// =====================================================
// MARK: - GamificationView
// [TAG: MOBILE_GAMIFICATION]
// =====================================================

struct GamificationView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var game: GamificationStore

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                progressCard
                skillsCard
                challengesCard
                recoveryCard
                seasonCard
                achievementsCard
            }
            .padding(16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Gamify")
    }

    private var progressCard: some View {
        GlassCard(title: "Progress", accent: settings.accentColor) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Level \(game.level)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text("XP \(game.totalXP)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                HStack {
                    Label("Momentum \(game.momentum)", systemImage: "waveform.path.ecg")
                    Spacer()
                    Text(game.specialization.selection.title)
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)

                Text(game.specialization.selection.summary)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)

                ProgressView(value: Double(game.momentum), total: 100)
                    .tint(settings.accentColor)

                Text("Weekly goal: \(game.weeklyGoal.completedDailyCompletions)/\(game.weeklyGoal.requiredDailyCompletions)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var skillsCard: some View {
        GlassCard(title: "Skills", accent: settings.accentColor) {
            VStack(spacing: 12) {
                RadarChartView(skills: game.skills, accent: settings.accentColor)
                    .frame(height: 230)

                ForEach(SkillCategory.allCases) { category in
                    let progress = game.skills[category]
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(category.title)
                            Spacer()
                            Text("Lv \(progress.level)")
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)

                        ProgressView(value: progress.progress0to1)
                            .tint(settings.accentColor)
                    }
                }
            }
        }
    }

    private var challengesCard: some View {
        GlassCard(title: "Challenges", accent: settings.accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                challengeSection(title: "Daily", items: game.dailyChallenges)
                challengeSection(title: "Weekly", items: game.weeklyChallenges)
                challengeSection(title: "Seasonal", items: game.seasonalChallenges)
            }
        }
    }

    private func challengeSection(title: String, items: [DailyChallenge]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)

            if items.isEmpty {
                Text("No active challenges")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(items) { challenge in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: challenge.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(challenge.completed ? .green : AppTheme.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(challenge.title)
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("\(challenge.progress)/\(challenge.target) • +\(challenge.rewardXP) XP")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                }
            }
        }
    }

    private var recoveryCard: some View {
        GlassCard(title: "Recovery / Reset", accent: settings.accentColor) {
            VStack(alignment: .leading, spacing: 8) {
                if let recovery = game.recoveryChallenge {
                    Text(recovery.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(recovery.detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)

                    HStack(spacing: 8) {
                        Button("Mark Recovery Complete") {
                            game.completeRecoveryChallenge()
                        }
                        .buttonStyle(.bordered)

                        if game.resetDayChallenge.isActive == false {
                            Button("Activate Reset Day") {
                                game.activateResetDayIfAvailable()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    if game.resetDayChallenge.isActive {
                        Text("Reset Day in progress")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                    } else {
                        Text("No active recovery challenge")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Button("Activate Reset Day") {
                        game.activateResetDayIfAvailable()
                    }
                    .buttonStyle(.bordered)
                }

                if game.resetDayChallenge.isActive {
                    Text("Reset challenge: Focus \(game.resetDayChallenge.focusProgress)/\(game.resetDayChallenge.focusTarget), Tasks \(game.resetDayChallenge.taskProgress)/\(game.resetDayChallenge.taskTarget), Habits \(game.resetDayChallenge.habitProgress)/\(game.resetDayChallenge.habitTarget)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    private var seasonCard: some View {
        GlassCard(title: "Season", accent: settings.accentColor) {
            VStack(alignment: .leading, spacing: 8) {
                Text(game.season.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Season XP: \(game.season.seasonalXP)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                Text("Perfect Days: \(game.season.stats.perfectDays) • Focus Sessions: \(game.season.stats.focusSessions)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var achievementsCard: some View {
        GlassCard(title: "Achievements", accent: settings.accentColor) {
            VStack(spacing: 8) {
                if game.achievements.isEmpty {
                    Text("No achievements unlocked yet")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(game.achievements.prefix(8)) { achievement in
                        HStack {
                            Image(systemName: achievement.icon)
                                .foregroundStyle(settings.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(achievement.title)
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text(achievement.detail)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer()
                            Text(achievement.tier.rawValue.capitalized)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
        }
    }
}
