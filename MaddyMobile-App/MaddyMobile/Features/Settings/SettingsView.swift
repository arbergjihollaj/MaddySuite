import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// File: Features/Settings/SettingsView.swift

// =====================================================
// MARK: - SettingsView
// [TAG: MOBILE_SETTINGS]
// =====================================================

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var calendarStore: CalendarStore

    @State private var showFolderPicker = false
    @State private var syncFolderStatusMessage = ""
    @State private var iCalURLInput = ""
    @State private var showAdvanced = false

    private let accentOptions: [String] = [
        "#FF7A2F", "#24C483", "#5AC8FA", "#FF375F", "#A284FF"
    ]

    var body: some View {
        Form {
            Section("General") {
                Toggle("Enable Sounds", isOn: $settings.soundEnabled)
                    .tint(settings.accentColor)

                Stepper("Daily task count: \(settings.dailyTaskCount)", value: $settings.dailyTaskCount, in: 1...8)

                Toggle("Show daily summary at 20:00", isOn: $settings.dailySummaryEnabled)
                    .tint(settings.accentColor)
            }

            Section("Appearance") {
                HStack(spacing: 10) {
                    ForEach(accentOptions, id: \.self) { hex in
                        let isSelected = settings.accentHex == hex
                        Button {
                            settings.accentHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex) ?? .orange)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Accent color \(hex)")
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Productivity") {
                Toggle("Enable Export Placeholder", isOn: $settings.exportPlaceholderEnabled)
                    .tint(settings.accentColor)

                ForEach(MobileTab.orderedCases) { tab in
                    HStack {
                        Label(tab.title, systemImage: tab.systemImage)
                        Spacer()
                        if tab.isAlwaysVisible {
                            Text("Always on")
                                .foregroundStyle(.secondary)
                        } else {
                            Toggle("", isOn: Binding(
                                get: { settings.isTabVisible(tab) },
                                set: { settings.setTabVisibility(tab, isVisible: $0) }
                            ))
                            .labelsHidden()
                            .tint(settings.accentColor)
                        }
                    }
                }
            }

            Section("Calendar & Integrations") {
                HStack(spacing: 10) {
                    Image(systemName: calendarStore.googleConnectionState.symbolName)
                        .foregroundStyle(settings.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google Calendar")
                            .font(.subheadline.weight(.semibold))
                        Text(calendarStore.googleConnectionState.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                HStack {
                    Button("Connect") { calendarStore.requestGoogleConnection() }
                    Button("Refresh") {
                        Task { await calendarStore.refreshAll(forceCalendarPermissionPrompt: false) }
                    }
                    Button("iOS Settings") { calendarStore.openSystemSettings() }
                }
                .buttonStyle(.bordered)

                Toggle("Show Google Calendar events", isOn: $settings.showGoogleCalendarEvents)
                    .tint(settings.accentColor)
                Toggle("Show iCal subscription events", isOn: $settings.showICalCalendarEvents)
                    .tint(settings.accentColor)
                Toggle("Show Maddy tasks with date", isOn: $settings.showTaskCalendarEntries)
                    .tint(settings.accentColor)

                VStack(alignment: .leading, spacing: 8) {
                    Text("iCal Subscriptions")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 8) {
                        TextField("https://example.com/calendar.ics", text: $iCalURLInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .font(.caption.monospaced())

                        Button {
                            let success = settings.addICalSubscription(urlString: iCalURLInput)
                            if success {
                                iCalURLInput = ""
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(settings.accentColor)
                    }

                    if settings.iCalSubscriptions.isEmpty {
                        Text("No subscriptions added")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(settings.iCalSubscriptions) { subscription in
                            iCalSubscriptionRow(subscription)
                        }
                    }
                }
            }

            Section("Sync") {
                HStack(spacing: 10) {
                    Image(systemName: appModel.syncStatus.iconName)
                        .foregroundStyle(settings.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appModel.syncStatus.title)
                            .font(.subheadline.weight(.semibold))
                        Text(appModel.syncStatus.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Enable Folder Sync (iCloud Drive)", isOn: $settings.iCloudSyncEnabled)
                    .tint(settings.accentColor)

                HStack {
                    if let lastSync = appModel.lastSuccessfulSyncAt {
                        Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No successful sync yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        appModel.triggerManualSync()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(settings.accentColor)
                    .disabled((settings.iCloudSyncEnabled == false && settings.backendSyncEnabled == false) || appModel.syncStatus == .syncing)
                }
            }

            Section("Advanced") {
                DisclosureGroup(isExpanded: $showAdvanced) {
                    Toggle("Enable Backend Sync (API)", isOn: $settings.backendSyncEnabled)
                        .tint(settings.accentColor)

                    TextField("Backend Base URL", text: $settings.backendBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.caption.monospaced())

                    HStack {
                        Text("Device ID")
                        Spacer()
                        Text(settings.backendClientDeviceID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button("Regenerate Device ID") {
                        settings.regenerateBackendClientDeviceID()
                    }

                    HStack {
                        Text("Sync Folder")
                        Spacer()
                        Text(appModel.syncFolderDisplayName)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    HStack {
                        Button("Select Folder") {
                            syncFolderStatusMessage = ""
                            showFolderPicker = true
                        }
                        .buttonStyle(.bordered)

                        Button("Clear", role: .destructive) {
                            appModel.clearSyncFolder()
                        }
                        .buttonStyle(.bordered)
                        .disabled(settings.hasSyncFolder == false)
                    }

                    if syncFolderStatusMessage.isEmpty == false {
                        Text(syncFolderStatusMessage)
                            .font(.caption)
                            .foregroundStyle(syncFolderStatusMessage.contains("failed") ? .orange : .green)
                    }
                } label: {
                    Text("Developer & Technical Options")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .sheet(isPresented: $showFolderPicker) {
            SyncFolderPicker(isPresented: $showFolderPicker) { url in
                let hasSecurityScope = url.startAccessingSecurityScopedResource()
                defer {
                    if hasSecurityScope {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let success = appModel.setSyncFolder(url)
                syncFolderStatusMessage = success ? "Folder selected" : "Folder save failed"
            }
        }
    }

    private func iCalSubscriptionRow(_ subscription: ICalSubscription) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { subscription.isEnabled },
                set: { settings.updateICalSubscriptionEnabled(id: subscription.id, isEnabled: $0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(subscription.name)
                        .font(.subheadline.weight(.semibold))
                    Text(subscription.urlString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let error = subscription.lastError, error.isEmpty == false {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else if let refreshedAt = subscription.lastRefreshAt {
                        Text("Updated \(refreshedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(settings.accentColor)

            Button(role: .destructive) {
                settings.removeICalSubscription(id: subscription.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove subscription")
        }
    }
}

// MARK: - Folder Picker

private struct SyncFolderPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: SyncFolderPicker

        init(parent: SyncFolderPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                parent.isPresented = false
                return
            }
            parent.onPick(url)
            parent.isPresented = false
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}
