import SwiftUI

/// File: Features/Tasks/TasksView.swift

// =====================================================
// MARK: - TasksView
// [TAG: MOBILE_TASKS]
// =====================================================

struct TasksView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var tasksStore: TasksStore

    @State private var selectedStatus: TaskStatus = .backlog
    @State private var editorTask: TaskItem?

    var body: some View {
        VStack(spacing: 12) {
            Picker("Status", selection: $selectedStatus) {
                ForEach(TaskStatus.allCases) { status in
                    Text(status.title).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            List {
                if selectedStatus == .done {
                    doneArchiveSection
                } else {
                    activeTasksSection
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Tasks")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTask = TaskItem.empty()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editorTask) { task in
            TaskEditorSheet(task: task) { updated in
                tasksStore.upsert(updated)
                editorTask = nil
            } onDelete: { id in
                tasksStore.delete(id: id)
                editorTask = nil
            }
            .presentationDetents([.medium, .large])
            .preferredColorScheme(.dark)
        }
    }

    private var activeTasksSection: some View {
        Section {
            let items = tasksStore.tasks(for: selectedStatus)
            if items.isEmpty {
                Text("No tasks in \(selectedStatus.title)")
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(items) { task in
                    Button {
                        editorTask = task
                    } label: {
                        taskRow(task)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            tasksStore.delete(id: task.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if selectedStatus == .backlog {
                            Button {
                                tasksStore.moveToStatus(taskID: task.id, status: .inProgress)
                            } label: {
                                Label("Start", systemImage: "play")
                            }
                            .tint(.blue)
                        } else if selectedStatus == .inProgress {
                            Button {
                                tasksStore.moveToStatus(taskID: task.id, status: .done)
                            } label: {
                                Label("Done", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
        }
    }

    private var doneArchiveSection: some View {
        Section {
            if tasksStore.archivedTasks.isEmpty {
                Text("No archived tasks yet")
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                ForEach(tasksStore.archivedTasks) { archived in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(archived.task.title)
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(archived.archivedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        Spacer()
                        Button {
                            tasksStore.restoreArchived(id: archived.id)
                        } label: {
                            Image(systemName: "arrow.uturn.left")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Archive")
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        GlassCard(accent: settings.accentColor) {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                HStack(spacing: 8) {
                    if let dueDate = task.dueDate {
                        Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    }

                    if task.tags.isEmpty == false {
                        Text(task.tags.joined(separator: ", "))
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: 6) {
                    Text(task.priority.title)
                    Text(task.difficulty.title)
                    if task.isDailyTask {
                        Text("Daily")
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.top, 2)
                .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}
