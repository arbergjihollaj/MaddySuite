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
        List {
            Section {
                GlassCard(title: "Today", accent: settings.accentColor) {
                    Text("Progress: \(habitsStore.todayProgressText)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                GlassCard(title: "Year Heatmap", accent: settings.accentColor) {
                    YearHeatmapView(
                        year: Calendar.current.component(.year, from: Date()),
                        values: habitsStore.totalCompletions(forYear: Calendar.current.component(.year, from: Date())),
                        tint: settings.accentColor
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(habitsStore.habits) { habit in
                    let isCompletedToday = isHabitCompletedToday(habit)
                    HabitRowView(habit: habit, accent: settings.accentColor, isCompletedToday: isCompletedToday) {
                        habitsStore.markCompleted(id: habit.id)
                    } onEdit: {
                        editorHabit = habit
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            habitsStore.markCompleted(id: habit.id)
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle.fill")
                        }
                        .tint(.green)
                        .disabled(isCompletedToday)
                    }
                }

                if habitsStore.habits.isEmpty {
                    GlassCard(accent: settings.accentColor) {
                        Text("No habits yet")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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

    private func isHabitCompletedToday(_ habit: Habit, now: Date = Date()) -> Bool {
        let key = HabitStore.dayKey(now)
        return (habit.history[key] ?? 0) >= habit.targetValue
    }
}

// =====================================================
// MARK: - HabitRowView
// [TAG: MOBILE_HABIT_ROW]
// =====================================================

private struct HabitRowView: View {
    let habit: Habit
    let accent: Color
    let isCompletedToday: Bool
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
                    Image(systemName: pulse || isCompletedToday ? "checkmark.circle.fill" : habit.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(hex: habit.colorHex) ?? accent)
                        .scaleEffect(pulse ? 1.22 : 1.0)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(isCompletedToday ? "Completed today  •  Streak: \(habit.streak)" : "Streak: \(habit.streak)  •  Target: \(habit.targetValue)")
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
