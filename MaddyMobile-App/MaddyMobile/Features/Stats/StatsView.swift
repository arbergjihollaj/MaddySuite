import SwiftUI

/// File: Features/Stats/StatsView.swift

// =====================================================
// MARK: - StatsView
// [TAG: MOBILE_STATS]
// =====================================================

struct StatsView: View {
    enum FocusScope: String, CaseIterable, Identifiable {
        case day
        case week
        case month

        var id: String { rawValue }

        var title: String {
            rawValue.capitalized
        }
    }

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var tasks: TasksStore
    @EnvironmentObject private var habits: HabitStore
    @EnvironmentObject private var game: GamificationStore

    @State private var scope: FocusScope = .day

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                GlassCard(title: "Focus", accent: settings.accentColor) {
                    Picker("Scope", selection: $scope) {
                        ForEach(FocusScope.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    FocusMiniChart(values: focusValues, accent: settings.accentColor)
                        .frame(height: 150)
                }

                GlassCard(title: "Productivity", accent: settings.accentColor) {
                    VStack(alignment: .leading, spacing: 8) {
                        statRow("Today focus", "\(focus.todayFocusMinutes) min")
                        statRow("Open tasks", "\(tasks.openCount)")
                        statRow("Tasks done", "\(tasks.archivedTasks.count)")
                        statRow("Habits done today", habits.todayProgressText)
                    }
                }

                GlassCard(title: "XP Growth", accent: settings.accentColor) {
                    FocusMiniChart(values: xpValues, accent: settings.accentColor)
                        .frame(height: 120)
                }
            }
            .padding(16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Stats")
    }

    private var focusValues: [Double] {
        switch scope {
        case .day:
            return dayFocusBuckets()
        case .week:
            return weekFocusBuckets()
        case .month:
            return monthFocusBuckets()
        }
    }

    private var xpValues: [Double] {
        Array(game.xpEntries.prefix(10).reversed()).map { Double($0.totalXP) }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
    }

    private func dayFocusBuckets() -> [Double] {
        var buckets = Array(repeating: 0.0, count: 24)
        let calendar = Calendar.current
        for session in focus.sessions where calendar.isDateInToday(session.startDate) {
            let hour = calendar.component(.hour, from: session.startDate)
            buckets[hour] += Double(session.durationMinutes)
        }
        return buckets
    }

    private func weekFocusBuckets() -> [Double] {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return Array(repeating: 0.0, count: 7)
        }

        var buckets = Array(repeating: 0.0, count: 7)
        for session in focus.sessions {
            let day = calendar.dateComponents([.day], from: start, to: session.startDate).day ?? -1
            if day >= 0 && day < 7 {
                buckets[day] += Double(session.durationMinutes)
            }
        }
        return buckets
    }

    private func monthFocusBuckets() -> [Double] {
        let calendar = Calendar.current
        guard let monthRange = calendar.range(of: .day, in: .month, for: Date()),
              let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) else {
            return []
        }

        var buckets = Array(repeating: 0.0, count: monthRange.count)
        for session in focus.sessions {
            let day = calendar.dateComponents([.day], from: start, to: session.startDate).day ?? -1
            if day >= 0 && day < monthRange.count {
                buckets[day] += Double(session.durationMinutes)
            }
        }
        return buckets
    }
}

private struct FocusMiniChart: View {
    let values: [Double]
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 1, 1)
            let count = max(values.count, 1)
            let totalGap = CGFloat(count - 1) * 3
            let width = max(2, (geo.size.width - totalGap) / CGFloat(count))

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(accent.opacity(0.85))
                        .frame(width: width, height: max(3, CGFloat(value / maxValue) * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}
