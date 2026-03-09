import SwiftUI
import UniformTypeIdentifiers

/// File: Features/Settings/SettingsView.swift

// =====================================================
// MARK: - SettingsView
// [TAG: MOBILE_SETTINGS]
// =====================================================

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @State private var showFolderPicker = false

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

                        Text("Maddy stays fully usable offline. Sync writes JSON snapshots into your selected iCloud Drive folder.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .padding(16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            _ = appModel.setSyncFolder(url)
        }
    }
}
