import SwiftUI

/// File: Features/Habits/HabitsView.swift

// =====================================================
// MARK: - HabitsView
// [TAG: MOBILE_HABITS]
// =====================================================

struct HabitsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var habitsStore: HabitStore

    @State private var editorHabit: Habit?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                GlassCard(title: "Today", accent: settings.accentColor) {
                    Text("Progress: \(habitsStore.todayProgressText)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                GlassCard(title: "Year Heatmap", accent: settings.accentColor) {
                    YearHeatmapView(
                        year: Calendar.current.component(.year, from: Date()),
                        values: habitsStore.totalCompletions(forYear: Calendar.current.component(.year, from: Date())),
                        tint: settings.accentColor
                    )
                }

                VStack(spacing: 10) {
                    ForEach(habitsStore.habits) { habit in
                        HabitRowView(habit: habit, accent: settings.accentColor) {
                            habitsStore.markCompleted(id: habit.id)
                        } onEdit: {
                            editorHabit = habit
                        }
                    }

                    if habitsStore.habits.isEmpty {
                        GlassCard(accent: settings.accentColor) {
                            Text("No habits yet")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Habits")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorHabit = Habit.empty()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editorHabit) { habit in
            HabitEditorSheet(habit: habit) { updated in
                habitsStore.upsert(updated)
            } onDelete: { id in
                habitsStore.delete(id: id)
            }
            .presentationDetents([.large])
            .preferredColorScheme(.dark)
        }
    }
}

// =====================================================
// MARK: - HabitRowView
// [TAG: MOBILE_HABIT_ROW]
// =====================================================

private struct HabitRowView: View {
    let habit: Habit
    let accent: Color
    let onComplete: () -> Void
    let onEdit: () -> Void

    @State private var pulse = false

    var body: some View {
        GlassCard(accent: accent) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(duration: 0.25, bounce: 0.45)) {
                        pulse = true
                    }
                    onComplete()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        withAnimation(.easeOut(duration: 0.16)) {
                            pulse = false
                        }
                    }
                } label: {
                    Image(systemName: pulse ? "checkmark.circle.fill" : habit.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(hex: habit.colorHex) ?? accent)
                        .scaleEffect(pulse ? 1.22 : 1.0)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("Streak: \(habit.streak)  •  Target: \(habit.targetValue)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Spacer()

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}
