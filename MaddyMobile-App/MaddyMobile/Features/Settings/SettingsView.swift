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

    private let accentOptions: [String] = [
        "#FF7A2F", "#24C483", "#5AC8FA", "#FF375F", "#A284FF"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                GlassCard(title: "Appearance", accent: settings.accentColor) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Accent")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)

                        HStack(spacing: 10) {
                            ForEach(accentOptions, id: \.self) { hex in
                                let isSelected = settings.accentHex == hex
                                Circle()
                                    .fill(Color(hex: hex) ?? .orange)
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Circle().stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        settings.accentHex = hex
                                    }
                            }
                        }
                    }
                }

                GlassCard(title: "Sound", accent: settings.accentColor) {
                    Toggle("Enable Sounds", isOn: $settings.soundEnabled)
                        .tint(settings.accentColor)
                }

                GlassCard(title: "Export", accent: settings.accentColor) {
                    Toggle("Enable Export Placeholder", isOn: $settings.exportPlaceholderEnabled)
                        .tint(settings.accentColor)

                    Text("Offline-only export hooks can be added here later.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                GlassCard(title: "Gameplay Loop", accent: settings.accentColor) {
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper("Daily task count: \(settings.dailyTaskCount)", value: $settings.dailyTaskCount, in: 1...8)
                        Toggle("Show daily summary at 20:00", isOn: $settings.dailySummaryEnabled)
                            .tint(settings.accentColor)
                        Text("Daily tasks are generated each day and feed progression, reliability, and momentum.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                GlassCard(title: "Tab Bar", accent: settings.accentColor) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(MobileTab.orderedCases) { tab in
                            HStack(spacing: 10) {
                                Label(tab.title, systemImage: tab.systemImage)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Spacer()

                                if tab.isAlwaysVisible {
                                    Text("Always on")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.textSecondary)
                                } else {
                                    Toggle("", isOn: Binding(
                                        get: { settings.isTabVisible(tab) },
                                        set: { settings.setTabVisibility(tab, isVisible: $0) }
                                    ))
                                    .labelsHidden()
                                    .tint(settings.accentColor)
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        Text("Home and More stay visible so navigation and Settings are always reachable.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                // =====================================================
                // MARK: - Calendar Settings
                // [TAG: MOBILE_SETTINGS_CALENDAR]
                // =====================================================
                GlassCard(title: "Calendar", accent: settings.accentColor) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: calendarStore.googleConnectionState.symbolName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(settings.accentColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Google Calendar")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text(calendarStore.googleConnectionState.subtitle)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }

                        HStack(spacing: 8) {
                            Button {
                                calendarStore.requestGoogleConnection()
                            } label: {
                                Label("Connect", systemImage: "link")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .buttonStyle(.bordered)

                            Button {
                                Task {
                                    await calendarStore.refreshAll(forceCalendarPermissionPrompt: false)
                                }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .buttonStyle(.bordered)

                            Button {
                                calendarStore.openSystemSettings()
                            } label: {
                                Label("iOS Settings", systemImage: "gear")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .buttonStyle(.bordered)
                        }

                        Divider().overlay(Color.white.opacity(0.08))

                        Toggle("Show Google Calendar events", isOn: $settings.showGoogleCalendarEvents)
                            .tint(settings.accentColor)

                        Toggle("Show iCal subscription events", isOn: $settings.showICalCalendarEvents)
                            .tint(settings.accentColor)

                        Toggle("Show Maddy tasks with date", isOn: $settings.showTaskCalendarEntries)
                            .tint(settings.accentColor)

                        Divider().overlay(Color.white.opacity(0.08))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("iCal Subscriptions")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textPrimary)

                            HStack(spacing: 8) {
                                TextField("https://example.com/calendar.ics", text: $iCalURLInput)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.white.opacity(0.05))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )

                                Button {
                                    let success = settings.addICalSubscription(urlString: iCalURLInput)
                                    if success {
                                        iCalURLInput = ""
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .frame(width: 34, height: 34)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(settings.accentColor)
                            }

                            if settings.iCalSubscriptions.isEmpty {
                                Text("No subscriptions added")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.textSecondary)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(settings.iCalSubscriptions) { subscription in
                                        iCalSubscriptionRow(subscription)
                                    }
                                }
                            }

                            Text("Subscriptions sync across iPhone and Mac when Folder Sync is enabled.")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }

                // =====================================================
                // MARK: - iCloud Sync
                // [TAG: MOBILE_SETTINGS_ICLOUD_SYNC]
                // =====================================================
                GlassCard(title: "iCloud Sync", accent: settings.accentColor) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: appModel.syncStatus.iconName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(settings.accentColor)
                                .rotationEffect(appModel.syncStatus == .syncing ? .degrees(360) : .degrees(0))
                                .animation(
                                    appModel.syncStatus == .syncing
                                        ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                                        : .default,
                                    value: appModel.syncStatus
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(appModel.syncStatus.title)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text(appModel.syncStatus.subtitle)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }

                        Toggle("Enable Folder Sync (iCloud Drive)", isOn: $settings.iCloudSyncEnabled)
                            .tint(settings.accentColor)

                        Divider().overlay(Color.white.opacity(0.08))

                        Toggle("Enable Backend Sync (API)", isOn: $settings.backendSyncEnabled)
                            .tint(settings.accentColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Backend Base URL")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)

                            TextField("http://127.0.0.1:4000/v1", text: $settings.backendBaseURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }

                        HStack(spacing: 8) {
                            Text("Device ID")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                            Text(settings.backendClientDeviceID)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Button("Regenerate") {
                                settings.regenerateBackendClientDeviceID()
                            }
                            .buttonStyle(.bordered)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sync Folder")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                            Text(appModel.syncFolderDisplayName)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)
                        }

                        HStack(spacing: 8) {
                            Button {
                                syncFolderStatusMessage = ""
                                showFolderPicker = true
                            } label: {
                                Label("Select Folder", systemImage: "folder")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                appModel.clearSyncFolder()
                            } label: {
                                Label("Clear", systemImage: "trash")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .buttonStyle(.bordered)
                            .disabled(settings.hasSyncFolder == false)
                        }

                        if syncFolderStatusMessage.isEmpty == false {
                            Text(syncFolderStatusMessage)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(syncFolderStatusMessage.contains("failed") ? .orange : .green)
                        }

                        HStack {
                            if let lastSync = appModel.lastSuccessfulSyncAt {
                                Text("Last sync: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.textSecondary)
                            } else {
                                Text("No successful sync yet")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Spacer()

                            Button {
                                appModel.triggerManualSync()
                            } label: {
                                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(settings.accentColor)
                            .disabled(settings.iCloudSyncEnabled == false || appModel.syncStatus == .syncing)
                        }

                        Text("Maddy stays fully usable offline. Backend task sync can run first, folder sync remains available as fallback.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .padding(16)
        }
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
                syncFolderStatusMessage = success ? "Folder selected ✓" : "Folder save failed"
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
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(subscription.urlString)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)

                    if let error = subscription.lastError, error.isEmpty == false {
                        Text(error)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else if let refreshedAt = subscription.lastRefreshAt {
                        Text("Updated \(refreshedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .tint(settings.accentColor)

            Button(role: .destructive) {
                settings.removeICalSubscription(id: subscription.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// =====================================================
// MARK: - Sync Folder Picker
// [TAG: MOBILE_SYNC_FOLDER_PICKER]
// =====================================================

private struct SyncFolderPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
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

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            DispatchQueue.main.async {
                self.parent.isPresented = false
            }
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            DispatchQueue.main.async {
                if let url = urls.first {
                    self.parent.onPick(url)
                }
                self.parent.isPresented = false
            }
        }
    }
}
