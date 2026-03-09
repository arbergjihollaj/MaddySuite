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
                GlassCard(title: "Progress", accent: settings.accentColor) {
                    HStack {
                        Text("Level \(game.level)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Text("XP \(game.totalXP)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                GlassCard(title: "Skills", accent: settings.accentColor) {
                    VStack(spacing: 12) {
                        RadarChartView(skills: game.skills, accent: settings.accentColor)
                            .frame(height: 230)

                        ForEach(SkillCategory.allCases) { category in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(category.title)
                                    Spacer()
                                    Text("\(game.skills[category])")
                                }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)

                                ProgressView(value: Double(game.skills[category]), total: 100)
                                    .tint(settings.accentColor)
                            }
                        }
                    }
                }

                GlassCard(title: "Daily Challenges", accent: settings.accentColor) {
                    VStack(spacing: 8) {
                        ForEach(game.dailyChallenges) { challenge in
                            HStack {
                                Image(systemName: challenge.completed ? "checkmark.circle.fill" : "circle")
                                Text(challenge.title)
                                    .foregroundStyle(AppTheme.textPrimary)
                                Spacer()
                            }
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                    }
                }

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
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Gamification")
    }
}
