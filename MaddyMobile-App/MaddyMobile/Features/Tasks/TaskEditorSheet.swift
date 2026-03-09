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

    let onSave: (TaskItem) -> Void
    let onDelete: (UUID) -> Void

    init(task: TaskItem, onSave: @escaping (TaskItem) -> Void, onDelete: @escaping (UUID) -> Void) {
        _draft = State(initialValue: task)
        _tagsText = State(initialValue: task.tags.joined(separator: ", "))
        _hasDueDate = State(initialValue: task.dueDate != nil)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $draft.title)

                    Picker("Status", selection: $draft.status) {
                        ForEach(TaskStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }

                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: Binding(
                            get: { draft.dueDate ?? Date() },
                            set: { draft.dueDate = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                    }

                    TextField("Tags (comma separated)", text: $tagsText)
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

        onSave(next)
        dismiss()
    }
}
