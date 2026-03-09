//
//  TasksView.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

// =====================================================
// MARK: - TasksView
// [TAG: V2_TASKS_VIEW]
// =====================================================

enum TaskComposerMode {
    case create
    case edit(TaskItem)

    var title: String {
        switch self {
        case .create: return "New Task"
        case .edit: return "Edit Task"
        }
    }
}

private struct ArchiveToast: Identifiable, Equatable {
    var id = UUID()
    var archiveID: UUID
    var title: String
}

struct TasksView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("maddy.tasks.stateHueEnabled") private var taskStateHueEnabled: Bool = true

    @State private var showingEditor = false
    @State private var composerMode: TaskComposerMode = .create

    @State private var dragTaskID: UUID?
    @State private var highlightedLane: TaskStatus?

    @State private var archiveToast: ArchiveToast?
    @State private var archiveToastDismissWork: DispatchWorkItem?

    private var vm: TasksViewModel { appState.tasksViewModel }

    var body: some View {
        VStack(spacing: 14) {
            taskActions

            GeometryReader { geometry in
                let laneWidth = idealLaneWidth(for: geometry.size.width)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)

                        HStack(alignment: .top, spacing: 16) {
                            ForEach(TaskStatus.allCases) { status in
                                laneView(status: status, laneWidth: laneWidth)
                            }
                        }
                        .frame(maxWidth: 1120)

                        Spacer(minLength: 0)
                    }
                    .frame(minWidth: geometry.size.width)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
            .frame(minHeight: 560)
        }
        .sheet(isPresented: $showingEditor) {
            TaskEditorSheet(
                isPresented: $showingEditor,
                mode: composerMode,
                onDelete: { id in
                    vm.delete(taskID: id)
                    showingEditor = false
                }
            )
            .environmentObject(appState)
        }
        .onReceive(vm.$latestArchiveNotice.compactMap { $0 }) { notice in
            showArchiveToast(title: notice.title, archiveID: notice.archiveID)
        }
        .overlay(alignment: .bottomTrailing) {
            if let archiveToast {
                HStack(spacing: 10) {
                    Label("Task archived ✓", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(archiveToast.title)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 180, alignment: .leading)

                    Button("Undo") {
                        withAnimation(.spring(duration: 0.2, bounce: 0.1)) {
                            vm.undoArchive(archiveID: archiveToast.archiveID)
                            self.archiveToast = nil
                        }
                        archiveToastDismissWork?.cancel()
                        archiveToastDismissWork = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.accentColor)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        }
                )
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .padding(.trailing, 10)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: archiveToast)
    }

    private var taskActions: some View {
        HStack(spacing: 10) {
            Text("Drag cards to Done to archive")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                composerMode = .create
                vm.resetDraft(defaultPriority: appState.settings.taskDefaultPriority)
                showingEditor = true
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.accentColor)
        }
    }

    private func laneView(status: TaskStatus, laneWidth: CGFloat) -> some View {
        TaskLaneColumn(
            title: status.title,
            tasks: vm.tasks(for: status),
            laneStatus: status,
            laneWidth: laneWidth,
            accent: appState.accentColor,
            highlighted: highlightedLane == status,
            showsStateHue: taskStateHueEnabled,
            dragTaskID: $dragTaskID,
            highlightedLane: $highlightedLane,
            onCardTap: { task in
                composerMode = .edit(task)
                vm.beginEditing(task)
                showingEditor = true
            },
            onMoveTo: { task, nextStatus in
                withAnimation(.spring(duration: 0.24, bounce: 0.15)) {
                    vm.setStatus(nextStatus, for: task)
                }
            },
            onStartFocus: { task in
                vm.startFocus(for: task)
            },
            onMoveTask: { sourceID, targetStatus, beforeID in
                withAnimation(.spring(duration: 0.24, bounce: 0.15)) {
                    vm.moveTask(sourceID, to: targetStatus, before: beforeID)
                }
            }
        )
    }

    private func idealLaneWidth(for totalWidth: CGFloat) -> CGFloat {
        let usable = min(totalWidth, 1120)
        let candidate = (usable - 32) / 3
        return max(300, min(360, candidate))
    }

    private func showArchiveToast(title: String, archiveID: UUID) {
        archiveToastDismissWork?.cancel()
        withAnimation(.spring(duration: 0.22, bounce: 0.12)) {
            archiveToast = ArchiveToast(archiveID: archiveID, title: title)
        }

        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.18)) {
                archiveToast = nil
            }
        }
        archiveToastDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }
}

// =====================================================
// MARK: - Lane Column
// [TAG: V2_TASKS_KANBAN_LANE]
// =====================================================

private struct TaskLaneColumn: View {
    let title: String
    let tasks: [TaskItem]
    let laneStatus: TaskStatus
    let laneWidth: CGFloat
    let accent: Color
    let highlighted: Bool
    let showsStateHue: Bool

    @Binding var dragTaskID: UUID?
    @Binding var highlightedLane: TaskStatus?

    let onCardTap: (TaskItem) -> Void
    let onMoveTo: (TaskItem, TaskStatus) -> Void
    let onStartFocus: (TaskItem) -> Void
    let onMoveTask: (UUID, TaskStatus, UUID?) -> Void

    var body: some View {
        GlassCard(title: title, accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                if tasks.isEmpty {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .frame(height: 92)
                        .overlay {
                            Text(laneStatus == .done ? "Drop task here to archive" : "Drop task here")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                } else {
                    ForEach(tasks) { task in
                        TaskCardView(
                            task: task,
                            accent: accent,
                            showsStateHue: showsStateHue,
                            onTap: { onCardTap(task) },
                            onMoveTo: { onMoveTo(task, $0) },
                            onStartFocus: { onStartFocus(task) }
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)),
                            removal: .opacity.combined(with: .scale(scale: 0.9))
                        ))
                        .onDrag {
                            dragTaskID = task.id
                            return NSItemProvider(object: task.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: TaskCardDropDelegate(
                                targetTaskID: task.id,
                                targetStatus: laneStatus,
                                dragTaskID: $dragTaskID,
                                highlightedLane: $highlightedLane,
                                onMoveTask: onMoveTask
                            )
                        )
                    }
                }
            }
            .animation(.spring(duration: 0.24, bounce: 0.15), value: tasks)
        }
        .frame(width: laneWidth)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(highlighted ? accent.opacity(0.7) : .clear, lineWidth: 1.4)
                .animation(.easeInOut(duration: 0.18), value: highlighted)
        )
        .onDrop(
            of: [UTType.text],
            delegate: TaskLaneDropDelegate(
                laneStatus: laneStatus,
                dragTaskID: $dragTaskID,
                highlightedLane: $highlightedLane,
                onMoveTask: onMoveTask
            )
        )
    }
}

// =====================================================
// MARK: - Task Card
// [TAG: V2_TASK_CARD]
// =====================================================

private struct TaskCardView: View {
    let task: TaskItem
    let accent: Color
    let showsStateHue: Bool
    let onTap: () -> Void
    let onMoveTo: (TaskStatus) -> Void
    let onStartFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(2)

                    if task.tags.isEmpty == false {
                        Text(task.tags.joined(separator: " • "))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if let dueDate = task.dueDate {
                        Text("Due \(dueDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 6)

                Text(task.priority.rawValue.capitalized)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(priorityColor(task.priority).opacity(0.22), in: Capsule())
            }

            HStack {
                Menu("Move") {
                    ForEach(TaskStatus.allCases) { status in
                        Button(status.title) {
                            onMoveTo(status)
                        }
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))

                Button("Start Focus") {
                    onStartFocus()
                }
                .buttonStyle(.bordered)
                .font(.system(size: 11, weight: .medium, design: .rounded))

                Spacer(minLength: 0)

                if task.recurrence != .none {
                    Label(task.recurrence.rawValue.capitalized, systemImage: "repeat")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackgroundColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                }
        )
        .onTapGesture {
            onTap()
        }
    }

    private var cardBackgroundColor: Color {
        guard showsStateHue else {
            return Color.white.opacity(0.05)
        }

        switch task.status {
        case .backlog:
            return Color.blue.opacity(0.10)
        case .inProgress:
            return Color.orange.opacity(0.10)
        case .done:
            return Color.green.opacity(0.10)
        }
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .red
        }
    }
}

// =====================================================
// MARK: - Drop Delegates
// [TAG: V2_TASKS_DROP]
// =====================================================

private struct TaskCardDropDelegate: DropDelegate {
    let targetTaskID: UUID
    let targetStatus: TaskStatus

    @Binding var dragTaskID: UUID?
    @Binding var highlightedLane: TaskStatus?

    let onMoveTask: (UUID, TaskStatus, UUID?) -> Void

    func dropEntered(info: DropInfo) {
        highlightedLane = targetStatus
        guard let sourceID = dragTaskID, sourceID != targetTaskID else { return }
        onMoveTask(sourceID, targetStatus, targetTaskID)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        highlightedLane = nil
        dragTaskID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        highlightedLane = nil
    }
}

private struct TaskLaneDropDelegate: DropDelegate {
    let laneStatus: TaskStatus

    @Binding var dragTaskID: UUID?
    @Binding var highlightedLane: TaskStatus?

    let onMoveTask: (UUID, TaskStatus, UUID?) -> Void

    func dropEntered(info: DropInfo) {
        highlightedLane = laneStatus
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            highlightedLane = nil
            dragTaskID = nil
        }

        guard let sourceID = dragTaskID else { return false }
        onMoveTask(sourceID, laneStatus, nil)
        return true
    }

    func dropExited(info: DropInfo) {
        highlightedLane = nil
    }
}
