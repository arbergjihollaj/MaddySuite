import SwiftUI

/// File: Features/Tasks/TasksView.swift

// =====================================================
// MARK: - TasksView
// [TAG: MOBILE_TASKS]
// =====================================================

private enum TaskListFilter: String, CaseIterable, Identifiable {
    case backlog
    case inProgress
    case done
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backlog: return "Backlog"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        case .archive: return "Archive"
        }
    }

    var status: TaskStatus? {
        switch self {
        case .backlog: return .backlog
        case .inProgress: return .inProgress
        case .done: return .done
        case .archive: return nil
        }
    }
}

struct TasksView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var tasksStore: TasksStore

    @State private var selectedFilter: TaskListFilter = .backlog
    @State private var editorTask: TaskItem?
    @State private var pendingArchiveUndo: ArchivedTaskItem?
    @State private var archiveUndoDismissTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            Picker("List", selection: $selectedFilter) {
                ForEach(TaskListFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            List {
                if selectedFilter == .archive {
                    archiveSection
                } else if let status = selectedFilter.status {
                    tasksSection(for: status)
                } else {
                    EmptyView()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Tasks")
        .safeAreaInset(edge: .bottom) {
            if let pendingArchiveUndo {
                archiveUndoBanner(for: pendingArchiveUndo)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTask = TaskItem.empty()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Task")
                .accessibilityHint("Creates a new task")
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

    private func tasksSection(for status: TaskStatus) -> some View {
        Section {
            let items = tasksStore.tasks(for: status)
            if items.isEmpty {
                Text(emptyTitle(for: status))
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
                        if status == .done {
                            Button {
                                archive(task)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.gray)
                        }
                        Button(role: .destructive) {
                            tasksStore.delete(id: task.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if status == .backlog {
                            Button {
                                tasksStore.moveToStatus(taskID: task.id, status: .inProgress)
                            } label: {
                                Label("Start", systemImage: "play")
                            }
                            .tint(.blue)
                        } else if status == .inProgress {
                            Button {
                                tasksStore.moveToStatus(taskID: task.id, status: .done)
                            } label: {
                                Label("Done", systemImage: "checkmark")
                            }
                            .tint(.green)
                        } else if status == .done {
                            Button {
                                tasksStore.moveToStatus(taskID: task.id, status: .backlog)
                            } label: {
                                Label("Reopen", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        } header: {
            Text(status == .done ? "Completed" : status.title)
        }
    }

    private var archiveSection: some View {
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
                        .accessibilityLabel("Restore task")
                        .accessibilityHint("Moves this task back to active lists")
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
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let dueDate = task.dueDate {
                        Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    }

                    if task.tags.isEmpty == false {
                        Text(task.tags.joined(separator: ", "))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

                HStack(spacing: 6) {
                    Text(task.priority.title)
                    Text(task.difficulty.title)
                    if task.isDailyTask {
                        Text("Daily")
                    }
                    if task.status == .done, let completedAt = task.completedAt {
                        Text("Done \(completedAt.formatted(date: .omitted, time: .shortened))")
                    }
                }
                .font(.caption)
                .padding(.top, 2)
                .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to edit task")
    }

    private func emptyTitle(for status: TaskStatus) -> String {
        switch status {
        case .backlog:
            return "No tasks in Backlog"
        case .inProgress:
            return "No tasks in progress"
        case .done:
            return "No completed tasks yet"
        case .missed:
            return "No missed tasks"
        }
    }

    private func archive(_ task: TaskItem) {
        guard let archived = tasksStore.archive(taskID: task.id) else { return }
        showArchiveUndo(archived)
        selectedFilter = .archive
    }

    private func showArchiveUndo(_ archived: ArchivedTaskItem) {
        archiveUndoDismissTask?.cancel()
        pendingArchiveUndo = archived

        archiveUndoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                pendingArchiveUndo = nil
            }
        }
    }

    private func archiveUndoBanner(for archived: ArchivedTaskItem) -> some View {
        HStack(spacing: 10) {
            Label("Archived", systemImage: "archivebox.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(archived.task.title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
            Spacer()
            Button("Undo") {
                tasksStore.restoreArchived(id: archived.id)
                withAnimation(.easeInOut(duration: 0.2)) {
                    pendingArchiveUndo = nil
                }
                archiveUndoDismissTask?.cancel()
                archiveUndoDismissTask = nil
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(settings.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.75))
        )
    }
}
