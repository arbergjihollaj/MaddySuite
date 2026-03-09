import SwiftUI

/// File: Features/Home/HomeView.swift

// =====================================================
// MARK: - HomeView
// [TAG: MOBILE_HOME]
// =====================================================

struct HomeView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var tasks: TasksStore
    @EnvironmentObject private var habits: HabitStore
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var game: GamificationStore

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                summaryGrid

                GlassCard(title: "Today", accent: settings.accentColor) {
                    Text(motivationalLine)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
            .padding(16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Home")
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricCard("Focus", value: "\(focus.todayFocusMinutes) min", icon: "timer")
            metricCard("Tasks", value: "\(tasks.openCount)", icon: "checklist")
            metricCard("Habits", value: habits.todayProgressText, icon: "flame")
            metricCard("Level", value: "Lv \(game.level)  •  XP \(game.totalXP)", icon: "hexagon")
        }
    }

    private func metricCard(_ title: String, value: String, icon: String) -> some View {
        GlassCard(accent: settings.accentColor) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
    }

    private var motivationalLine: String {
        if focus.todayFocusMinutes >= focus.dailyGoalMinutes {
            return "Great momentum today. Keep the streak alive."
        }

        if tasks.openCount > 0 {
            return "Small steps now make tomorrow easier."
        }

        return "You are building consistency one session at a time."
    }
}
