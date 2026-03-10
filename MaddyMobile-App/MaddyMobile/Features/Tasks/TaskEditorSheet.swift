import SwiftUI

/// File: Features/Tasks/TaskEditorSheet.swift

// =====================================================
// MARK: - TaskEditorSheet
// [TAG: MOBILE_TASK_EDITOR]
// =====================================================

struct TaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TaskItem
    @State private var tagsText: String
    @State private var hasDueDate: Bool
    @State private var showDeleteConfirm = false
    @State private var showAdvanced = false
    @State private var primarySkill: TaskSkillTag
    @State private var secondarySkillEnabled: Bool
    @State private var secondarySkill: TaskSkillTag

    let onSave: (TaskItem) -> Void
    let onDelete: (UUID) -> Void

    init(task: TaskItem, onSave: @escaping (TaskItem) -> Void, onDelete: @escaping (UUID) -> Void) {
        _draft = State(initialValue: task)
        _tagsText = State(initialValue: task.tags.joined(separator: ", "))
        _hasDueDate = State(initialValue: task.dueDate != nil)
        let mapped = task.mappedSkills
        _primarySkill = State(initialValue: mapped.first ?? .execution)
        _secondarySkillEnabled = State(initialValue: mapped.count > 1)
        _secondarySkill = State(initialValue: mapped.dropFirst().first ?? .reliability)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Title", text: $draft.title)

                    Picker("Status", selection: $draft.status) {
                        ForEach(TaskStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                }

                Section("Planning") {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: Binding(
                            get: { draft.dueDate ?? Date() },
                            set: { draft.dueDate = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                    }

                    Toggle("Daily task", isOn: $draft.isDailyTask)
                    if draft.isDailyTask {
                        Toggle("Required daily task", isOn: $draft.isRequiredDailyTask)
                    }
                }

                Section("Priority & Difficulty") {
                    Picker("Difficulty", selection: $draft.difficulty) {
                        ForEach(TaskDifficulty.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }

                    Picker("Priority", selection: $draft.priority) {
                        ForEach(TaskPriority.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }

                    DisclosureGroup("Advanced options", isExpanded: $showAdvanced) {
                        TextField("Tags (comma separated)", text: $tagsText)

                        Picker("Primary skill", selection: $primarySkill) {
                            ForEach(TaskSkillTag.allCases) { tag in
                                Text(tag.title).tag(tag)
                            }
                        }

                        Toggle("Second skill", isOn: $secondarySkillEnabled)
                        if secondarySkillEnabled {
                            Picker("Secondary skill", selection: $secondarySkill) {
                                ForEach(TaskSkillTag.allCases) { tag in
                                    Text(tag.title).tag(tag)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(draft.title.isEmpty ? "New Task" : "Edit Task")
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
            .confirmationDialog("Delete task?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete(draft.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func saveAndClose() {
        var next = draft
        next.title = next.title.trimmingCharacters(in: .whitespacesAndNewlines)
        next.tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        if hasDueDate == false {
            next.dueDate = nil
        }

        next.mappedSkills = secondarySkillEnabled && secondarySkill != primarySkill
            ? [primarySkill, secondarySkill]
            : [primarySkill]
        if next.isDailyTask {
            next.dailyDateKey = TaskItem.dayKey(Date())
        } else {
            next.dailyDateKey = nil
        }

        onSave(next)
        dismiss()
    }
}
