import SwiftUI

/// File: Features/Habits/HabitEditorSheet.swift

// =====================================================
// MARK: - HabitEditorSheet
// [TAG: MOBILE_HABIT_EDITOR]
// =====================================================

struct HabitEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Habit
    @State private var color: Color
    @State private var showDeleteConfirm = false

    let onSave: (Habit) -> Void
    let onDelete: (UUID) -> Void

    private let weekdaySymbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    init(habit: Habit, onSave: @escaping (Habit) -> Void, onDelete: @escaping (UUID) -> Void) {
        _draft = State(initialValue: habit)
        _color = State(initialValue: Color(hex: habit.colorHex) ?? .green)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Habit name", text: $draft.title)
                    SymbolPicker(selectedSymbol: $draft.symbol)
                    ColorPicker("Color", selection: $color)
                }

                Section("Goal") {
                    Picker("Type", selection: $draft.goalKind) {
                        ForEach(HabitGoalKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    Stepper("Target: \(draft.targetValue)", value: $draft.targetValue, in: 1...300)
                }

                Section("Schedule") {
                    Picker("Mode", selection: $draft.scheduleMode) {
                        ForEach(HabitScheduleMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if draft.scheduleMode == .weekdays {
                        HStack {
                            ForEach(0..<7, id: \.self) { idx in
                                let selected = draft.weekdays.contains(idx + 2)
                                Button {
                                    toggleWeekday(idx + 2)
                                } label: {
                                    Text(weekdaySymbols[idx])
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(selected ? color.opacity(0.7) : Color.white.opacity(0.08))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        Stepper("Every \(draft.everyXDays) day(s)", value: $draft.everyXDays, in: 1...30)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Habit", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(draft.title.isEmpty ? "New Habit" : "Edit Habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAndClose()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete habit?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete(draft.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func toggleWeekday(_ day: Int) {
        if draft.weekdays.contains(day) {
            draft.weekdays.removeAll { $0 == day }
        } else {
            draft.weekdays.append(day)
            draft.weekdays.sort()
        }
    }

    private func saveAndClose() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.colorHex = color.hexString
        if draft.weekdays.isEmpty {
            draft.weekdays = [2, 3, 4, 5, 6]
        }
        onSave(draft)
        dismiss()
    }
}
