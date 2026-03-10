//
//  TaskEditorSheet.swift
//  MaddyV2
//
//  Created by Codex on 04.03.26.
//

import SwiftUI

// =====================================================
// MARK: - Task Editor Sheet
// [TAG: TASK_EDITOR_SHEET]
// =====================================================

struct TaskEditorSheet: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    let mode: TaskComposerMode
    let onDelete: (UUID) -> Void

    @State private var showsDeleteConfirm = false
    @State private var isHoveringSave = false

    private var vm: TasksViewModel { appState.tasksViewModel }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.35)

            ScrollView {
                VStack(spacing: 16) {
                    titleSection
                    planningSection
                    detailsSection

                    if case .edit = mode {
                        dangerZone
                    }

                    if let validation = vm.validationMessage, validation.isEmpty == false {
                        validationBanner(validation)
                    }
                }
                .padding(20)
            }

            Divider().opacity(0.35)

            footerActions
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .confirmationDialog("Delete task?", isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete(vm.draft.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .frame(minWidth: 620, minHeight: 540)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: modeIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(appState.accentColor)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(appState.accentColor.opacity(0.16))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(modeSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var titleSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Title", systemImage: "textformat")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                TextField("Task title", text: Binding(
                    get: { vm.draft.title },
                    set: { vm.draft.title = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                        }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        } label: {
            Text("Primary")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .groupBoxStyle(.automatic)
    }

    private var planningSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                taskFieldRow(icon: "calendar", label: "Due date") {
                    Toggle("", isOn: Binding(
                        get: { vm.draft.dueDate != nil },
                        set: { enabled in
                            vm.draft.dueDate = enabled ? (vm.draft.dueDate ?? Date()) : nil
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()

                    if vm.draft.dueDate != nil {
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { vm.draft.dueDate ?? Date() },
                                set: { vm.draft.dueDate = $0 }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    } else {
                        Text("No due date")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                taskFieldRow(icon: "tag", label: "Tag") {
                    TextField("Optional", text: Binding(
                        get: { vm.draft.tags.first ?? "" },
                        set: { value in
                            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            vm.draft.tags = clean.isEmpty ? [] : [clean]
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Planning")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .groupBoxStyle(.automatic)
    }

    private var detailsSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                taskFieldRow(icon: "rectangle.3.group", label: "Status") {
                    Picker("", selection: Binding(
                        get: { vm.draft.status },
                        set: { vm.draft.status = $0 }
                    )) {
                        ForEach(TaskStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }

                taskFieldRow(icon: "flag", label: "Priority") {
                    Picker("", selection: Binding(
                        get: { vm.draft.priority },
                        set: { vm.draft.priority = $0 }
                    )) {
                        ForEach(TaskPriority.allCases) { priority in
                            Text(priority.rawValue.capitalized).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Details")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .groupBoxStyle(.automatic)
    }

    private var dangerZone: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Delete this task permanently.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer(minLength: 0)
                    Button(role: .destructive) {
                        showsDeleteConfirm = true
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        } label: {
            Text("Danger Zone")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
        }
        .groupBoxStyle(.automatic)
    }

    private var footerActions: some View {
        HStack {
            Button("Cancel") {
                isPresented = false
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)

            Button {
                if vm.saveDraft(defaultPriority: appState.settings.taskDefaultPriority) {
                    isPresented = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                    Text("Save")
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(appState.accentColor.opacity(isHoveringSave ? 0.92 : 0.78))
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.14)) {
                    isHoveringSave = hovering
                }
            }
            .disabled(vm.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(vm.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.14))
    }

    private func validationBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.orange)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.orange.opacity(0.28), lineWidth: 0.8)
                }
        )
    }

    private func taskFieldRow<Content: View>(icon: String, label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)

            content()
            Spacer(minLength: 0)
        }
    }

    private var modeIcon: String {
        switch mode {
        case .create: return "plus.circle.fill"
        case .edit: return "square.and.pencil"
        }
    }

    private var modeSubtitle: String {
        switch mode {
        case .create:
            return "Create a task with clear priority and due date"
        case .edit:
            return "Adjust details, archive by marking done, or delete"
        }
    }
}
