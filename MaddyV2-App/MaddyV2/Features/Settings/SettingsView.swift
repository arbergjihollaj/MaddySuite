//
//  SettingsView.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI

// =====================================================
// MARK: - SettingsView
// [TAG: V2_SETTINGS_VIEW]
// =====================================================

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var serialService: SerialService
    @EnvironmentObject var fileShelfStore: FileShelfStore
    @Environment(\.openWindow) private var openWindow
    @State private var topBarOrderDraft: [AppRoute] = []
    @State private var statsStatusText: String = ""
    @State private var statsExportInFlight = false
    @State private var iCloudSyncInFlight = false
    @State private var iCloudSyncStatusText: String = ""
    @State private var showClearArchiveConfirm = false
    @State private var selectedCategory: SettingsCategory = .general
    @State private var iCalURLInput: String = ""
    @AppStorage("maddy.ai.showQuickActions") private var aiShowQuickActions: Bool = true
    @AppStorage("maddy.ai.showDailyChallenge") private var aiShowDailyChallenge: Bool = true
    @AppStorage("maddy.ai.showToolStrip") private var aiShowToolStrip: Bool = true
    @AppStorage("maddy.tasks.stateHueEnabled") private var taskStateHueEnabled: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            categorySidebar
            ScrollView {
                contentPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .onAppear {
            appState.showMenuBarHint = false
            if topBarOrderDraft.isEmpty {
                topBarOrderDraft = appState.topOrder
            }
        }
        .onChange(of: appState.topOrder) { _, newValue in
            topBarOrderDraft = newValue
        }
    }

    // =====================================================
    // MARK: - Category Hub
    // [TAG: SETTINGS_CATEGORY_CARDS]
    // =====================================================

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            ForEach(SettingsCategory.allCases) { category in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedCategory = category
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: category.icon)
                            .frame(width: 18)
                        Text(category.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selectedCategory == category ? appState.accentColor.opacity(0.22) : Color.white.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 210)
    }

    private var contentPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: selectedCategory.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(appState.accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedCategory.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(selectedCategory.subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            categoryContent
                .transition(.opacity)
                .id(selectedCategory.id)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch selectedCategory {
        case .general:
            generalSection
        case .appearance:
            appearanceSection
        case .productivity:
            VStack(spacing: 14) {
                focusSection
                habitsSection
                tasksSection
                statisticsSection
            }
        case .sync:
            iCloudSyncSection
        case .integrations:
            VStack(spacing: 14) {
                calendarSection
                aiSection
            }
        case .advanced:
            fileShelfSection
        case .developer:
            VStack(spacing: 14) {
                serialSection
                debugSection
            }
        }
    }

    private var generalSection: some View {
        GlassCard(title: "General", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable Menu Bar Mode", isOn: Binding(
                    get: { appState.settings.menuBarEnabled },
                    set: { appState.settings.menuBarEnabled = $0 }
                ))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Home Widgets")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack {
                        ForEach(HomeWidgetKind.allCases) { widget in
                            let selected = appState.settings.homeWidgets.contains(widget)
                            Button(widget.title) {
                                appState.toggleWidget(widget, enabled: selected == false)
                            }
                            .buttonStyle(.bordered)
                            .tint(selected ? appState.accentColor : .gray)
                        }
                    }
                }

                Text("Core settings stay here. Technical diagnostics are under Developer.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceSection: some View {
        GlassCard(title: "Appearance", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 12) {
                ColorPicker("Accent Color", selection: Binding(
                    get: { appState.accentColor },
                    set: {
                        appState.settings.accentHex = $0.toHex
                    }
                ))

                HStack {
                    Text("Glass Intensity")
                    Slider(value: Binding(
                        get: { appState.settings.glassIntensity },
                        set: { appState.settings.glassIntensity = $0 }
                    ), in: 0.15...0.9)
                    Text(String(format: "%.2f", appState.settings.glassIntensity))
                        .monospacedDigit()
                        .frame(width: 42)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Top Bar Order")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        Button("Reset") {
                            topBarOrderDraft = AppRoute.allCases
                            appState.persistTopOrder(topBarOrderDraft)
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("Drag the rows to reorder the icons in the top bar.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    List {
                        ForEach(topBarOrderDraft) { route in
                            HStack(spacing: 8) {
                                Image(systemName: route.icon)
                                    .frame(width: 18)
                                Text(route.title)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                Spacer()
                            }
                        }
                        .onMove { source, destination in
                            topBarOrderDraft = movedRoutes(topBarOrderDraft, from: source, to: destination)
                            appState.persistTopOrder(topBarOrderDraft)
                        }
                    }
                    .frame(height: 210)
                    .listStyle(.inset)
                }
            }
        }
    }

    private var serialSection: some View {
        GlassCard(title: "Serial", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Port", selection: Binding(
                        get: { serialService.selectedPort ?? "" },
                        set: {
                            let value = $0.isEmpty ? nil : $0
                            serialService.selectedPort = value
                            appState.settings.preferredSerialPort = value
                        }
                    )) {
                        Text("No Port").tag("")
                        ForEach(serialService.availablePorts, id: \.self) { port in
                            Text(port).tag(port)
                        }
                    }
                    .pickerStyle(.menu)

                    Button("Refresh") {
                        serialService.refreshPorts()
                    }

                    Button(serialService.isConnected ? "Disconnect" : "Connect") {
                        if serialService.isConnected {
                            serialService.disconnect()
                        } else {
                            serialService.connect()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.accentColor)
                }

                Toggle("Auto reconnect", isOn: Binding(
                    get: { appState.settings.autoReconnect },
                    set: { appState.settings.autoReconnect = $0 }
                ))

                Text("Status: \(serialService.status)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aiSection: some View {
        VStack(spacing: 14) {
            AISettingsView(ai: appState.aiService)

            GlassCard(title: "ESP AI Placeholder", accent: appState.accentColor) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Style", selection: Binding(
                        get: { appState.settings.aiPlaceholderStyle },
                        set: { appState.settings.aiPlaceholderStyle = $0 }
                    )) {
                        ForEach(AIPlaceholderStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Used when the AI/Coach page is active on the ESP display.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            GlassCard(title: "AI Screen Layout", accent: appState.accentColor) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Show Quick Actions", isOn: Binding(
                        get: { aiShowQuickActions },
                        set: { aiShowQuickActions = $0 }
                    ))

                    Toggle("Show Daily Challenge", isOn: Binding(
                        get: { aiShowDailyChallenge },
                        set: { aiShowDailyChallenge = $0 }
                    ))

                    Toggle("Show Tools Row", isOn: Binding(
                        get: { aiShowToolStrip },
                        set: { aiShowToolStrip = $0 }
                    ))
                }
            }
        }
    }

    private var focusSection: some View {
        GlassCard(title: "Focus", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 8) {
                Stepper("Daily Goal: \(appState.settings.dailyFocusGoal)", value: Binding(
                    get: { appState.settings.dailyFocusGoal },
                    set: {
                        appState.settings.dailyFocusGoal = max(1, $0)
                        appState.focusViewModel.dailyGoal = appState.settings.dailyFocusGoal
                    }
                ), in: 1...30)

                Toggle("Sound Effects", isOn: Binding(
                    get: { appState.settings.focusSoundEnabled },
                    set: { appState.settings.focusSoundEnabled = $0 }
                ))

                HStack {
                    Text("Sound Volume")
                    Slider(value: Binding(
                        get: { appState.settings.focusSoundVolume },
                        set: { appState.settings.focusSoundVolume = $0 }
                    ), in: 0...1)
                    Text("\(Int(appState.settings.focusSoundVolume * 100))%")
                        .monospacedDigit()
                        .frame(width: 44)
                }

                Divider().opacity(0.25)

                Stepper("Daily Task Count: \(appState.settings.dailyTaskCount)", value: Binding(
                    get: { appState.settings.dailyTaskCount },
                    set: { appState.settings.dailyTaskCount = max(1, min(8, $0)) }
                ), in: 1...8)

                Toggle("Show Daily Summary at 20:00", isOn: Binding(
                    get: { appState.settings.dailySummaryEnabled },
                    set: { appState.settings.dailySummaryEnabled = $0 }
                ))
            }
        }
    }

    private var tasksSection: some View {
        GlassCard(title: "Tasks", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Default Priority", selection: Binding(
                    get: { appState.settings.taskDefaultPriority },
                    set: { appState.settings.taskDefaultPriority = $0 }
                )) {
                    ForEach(TaskPriority.allCases) { priority in
                        Text(priority.rawValue.capitalized).tag(priority)
                    }
                }
                .pickerStyle(.segmented)

                Text("High priority tasks require due dates.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Toggle("Subtle lane hue by status", isOn: Binding(
                    get: { taskStateHueEnabled },
                    set: { taskStateHueEnabled = $0 }
                ))

                Divider().opacity(0.25)

                HStack {
                    Label("Archive", systemImage: "archivebox")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer(minLength: 0)
                    Text("\(appState.tasksViewModel.archivedTasks.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }

                if appState.tasksViewModel.archivedTasks.isEmpty {
                    Text("No archived tasks yet.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(appState.tasksViewModel.archivedTasks) { archived in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(archived.task.title)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .lineLimit(1)
                                        Text("Archived \(archived.archivedAt.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Button("Restore") {
                                        withAnimation(.spring(duration: 0.22, bounce: 0.12)) {
                                            appState.tasksViewModel.restoreArchived(archiveID: archived.id)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button(role: .destructive) {
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            appState.tasksViewModel.deleteArchived(archiveID: archived.id)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.white.opacity(0.04))
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 220)

                    HStack {
                        Spacer(minLength: 0)
                        Button(role: .destructive) {
                            showClearArchiveConfirm = true
                        } label: {
                            Label("Clear Archive", systemImage: "trash.slash")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .confirmationDialog("Clear archived tasks?", isPresented: $showClearArchiveConfirm, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        appState.tasksViewModel.clearArchive()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all archived tasks.")
            }
        }
    }

    private var habitsSection: some View {
        GlassCard(title: "Habits", accent: appState.accentColor) {
            Toggle("Week Starts Monday", isOn: Binding(
                get: { appState.settings.habitWeekStartsMonday },
                set: { appState.settings.habitWeekStartsMonday = $0 }
            ))
        }
    }

    private var calendarSection: some View {
        GlassCard(title: "Calendar Sources", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show Google Calendar events", isOn: Binding(
                    get: { appState.settings.showGoogleCalendarEvents },
                    set: { appState.settings.showGoogleCalendarEvents = $0 }
                ))

                Toggle("Show iCal subscription events", isOn: Binding(
                    get: { appState.settings.showICalCalendarEvents },
                    set: { appState.settings.showICalCalendarEvents = $0 }
                ))

                Toggle("Show Maddy tasks with date", isOn: Binding(
                    get: { appState.settings.showTaskCalendarEntries },
                    set: { appState.settings.showTaskCalendarEntries = $0 }
                ))

                Divider().opacity(0.2)

                VStack(alignment: .leading, spacing: 8) {
                    Text("iCal Subscriptions")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("https://example.com/calendar.ics", text: $iCalURLInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))

                        Button {
                            let success = appState.addICalSubscription(urlString: iCalURLInput)
                            if success {
                                iCalURLInput = ""
                            }
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(appState.accentColor)
                    }

                    if appState.settings.iCalSubscriptions.isEmpty {
                        Text("No subscriptions added yet.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(appState.settings.iCalSubscriptions) { subscription in
                                HStack(spacing: 10) {
                                    Toggle(isOn: Binding(
                                        get: { subscription.isEnabled },
                                        set: { appState.updateICalSubscriptionEnabled(id: subscription.id, isEnabled: $0) }
                                    )) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(subscription.name)
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .lineLimit(1)
                                            Text(subscription.urlString)
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                            if let error = subscription.lastError, error.isEmpty == false {
                                                Text(error)
                                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                                    .foregroundStyle(.orange)
                                                    .lineLimit(1)
                                            } else if let refreshedAt = subscription.lastRefreshAt {
                                                Text("Updated \(refreshedAt.formatted(date: .omitted, time: .shortened))")
                                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }

                                    Button(role: .destructive) {
                                        appState.removeICalSubscription(id: subscription.id)
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
                    }
                }

                Text("Subscriptions sync across iPhone and Mac via your shared folder sync.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // =====================================================
    // MARK: - iCloud Sync Settings
    // [TAG: V2_SETTINGS_ICLOUD_SYNC]
    // =====================================================
    private var iCloudSyncSection: some View {
        GlassCard(title: "Folder Sync", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    Image(systemName: appState.cloudSyncStatusIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(appState.accentColor)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.cloudSyncStatusTitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(appState.cloudSyncStatusDetail)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                Toggle("Enable Folder Sync (iCloud Drive)", isOn: Binding(
                    get: { appState.settings.iCloudSyncEnabled },
                    set: { appState.settings.iCloudSyncEnabled = $0 }
                ))

                Divider().overlay(Color.white.opacity(0.08))

                Toggle("Enable Backend Sync (API)", isOn: Binding(
                    get: { appState.settings.backendSyncEnabled },
                    set: { appState.settings.backendSyncEnabled = $0 }
                ))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Backend Base URL")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    TextField("http://127.0.0.1:4000/v1", text: Binding(
                        get: { appState.settings.backendBaseURL },
                        set: { appState.settings.backendBaseURL = $0 }
                    ))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 8) {
                    Text("Device ID")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(appState.settings.backendClientDeviceID)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Regenerate") {
                        appState.settings.backendClientDeviceID = "mac-\(UUID().uuidString.lowercased())"
                    }
                    .buttonStyle(.bordered)
                }

                Text("Backend sync is task-focused and runs before folder sync when enabled.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sync Folder")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(appState.syncFolderDisplayPath)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Button {
                        appState.pickSyncFolder()
                    } label: {
                        Label("Select Folder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        appState.openSyncFolderInFinder()
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.hasConfiguredSyncFolder == false)

                    Button(role: .destructive) {
                        appState.clearSyncFolder()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.hasConfiguredSyncFolder == false)
                }

                HStack(spacing: 10) {
                    Button {
                        Task {
                            iCloudSyncInFlight = true
                            let success = await appState.syncWithICloudNow()
                            iCloudSyncInFlight = false
                            iCloudSyncStatusText = success ? "Sync complete ✓" : "Sync failed"
                        }
                    } label: {
                        Label(iCloudSyncInFlight ? "Syncing..." : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.accentColor)
                    .disabled(iCloudSyncInFlight || appState.settings.iCloudSyncEnabled == false || appState.hasConfiguredSyncFolder == false)

                    if let last = appState.cloudSyncLastSuccessfulAt {
                        Text("Last: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if iCloudSyncStatusText.isEmpty == false {
                    Text(iCloudSyncStatusText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(iCloudSyncStatusText.contains("failed") ? .orange : .green)
                }

                Text("Offline-first: local data stays available. Backend task sync can run first, folder sync remains the legacy fallback.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // =====================================================
    // MARK: - Statistics Settings
    // [TAG: V2_SETTINGS_STATS_EXPORT]
    // =====================================================
    private var statisticsSection: some View {
        GlassCard(title: "Statistics", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Auto Export (every 60 minutes)", isOn: Binding(
                    get: { appState.settings.autoExportStatistics },
                    set: { appState.settings.autoExportStatistics = $0 }
                ))

                HStack(spacing: 10) {
                    Button {
                        Task {
                            statsExportInFlight = true
                            let success = await appState.exportStatisticsNow()
                            statsExportInFlight = false
                            statsStatusText = success ? "Excel updated ✓" : "Export failed"
                        }
                    } label: {
                        Label(statsExportInFlight ? "Exporting..." : "Export Now", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.accentColor)
                    .disabled(statsExportInFlight)

                    Button {
                        Task {
                            let opened = await appState.openStatisticsWorkbook()
                            if opened == false {
                                statsStatusText = "Export failed"
                            }
                        }
                    } label: {
                        Label("Open Excel File", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                }

                if let exportedAt = appState.statisticsLastExportDate {
                    Text("Last export: \(exportedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if statsStatusText.isEmpty == false {
                    Text(statsStatusText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(statsStatusText.contains("failed") ? .orange : .green)
                } else if let error = appState.statisticsLastExportError {
                    Text(error)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // =====================================================
    // MARK: - File Shelf Settings
    // [TAG: FILE_SHELF_SETTINGS]
    // =====================================================
    private var fileShelfSection: some View {
        GlassCard(title: "File Shelf", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Parked Files", systemImage: fileShelfStore.hasItems ? "tray.full.fill" : "tray")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Spacer(minLength: 0)
                    Text("\(fileShelfStore.items.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }

                Text("Temporary shelf for local file references. Files are never copied or deleted.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        openWindow(id: FileShelfWindowID.panel)
                    } label: {
                        Label("Open Shelf", systemImage: "rectangle.on.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.accentColor)

                    Button(role: .destructive) {
                        fileShelfStore.clearAll()
                    } label: {
                        Label("Clear Shelf", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(fileShelfStore.items.isEmpty)
                }
            }
        }
    }

    private var debugSection: some View {
        GlassCard(title: "Debug Console", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 12) {
                // =====================================================
                // MARK: - Serial Diagnostics
                // [TAG: SERIAL_AUTOCONNECT]
                // =====================================================
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Serial Diagnostics", systemImage: "cable.connector")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Spacer(minLength: 0)
                        Text(serialService.isConnected ? "Connected" : (serialService.autoReconnectEnabled ? "Reconnecting" : "Disconnected"))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(serialService.isConnected ? .green : (serialService.autoReconnectEnabled ? .orange : .red))
                    }

                    Text("Connection state: \(serialService.status)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("lastConnectedPort: \(serialService.lastConnectedPort ?? "—")")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text("lastGamifyTX: \(serialService.lastGamifyPayload ?? "—")")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Button("Refresh ports") {
                            serialService.refreshPorts()
                        }
                        .buttonStyle(.bordered)

                        Button("Force reconnect") {
                            serialService.forceReconnect()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(appState.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if serialService.availablePortDebugInfo.isEmpty {
                            Text("No serial ports detected.")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(serialService.availablePortDebugInfo) { info in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(info.name)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .lineLimit(1)
                                    Text(info.path)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.04))
                                )
                            }
                        }
                    }
                }

                Divider().opacity(0.2)

                Toggle("Enable Debug Logs", isOn: Binding(
                    get: { appState.settings.debugLogsEnabled },
                    set: { appState.settings.debugLogsEnabled = $0 }
                ))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(serialService.debugLines.suffix(150), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minHeight: 180)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.38))
                )
            }
        }
    }

    private func movedRoutes(_ values: [AppRoute], from source: IndexSet, to destination: Int) -> [AppRoute] {
        var array = values
        let moving = source.sorted().map { array[$0] }
        for index in source.sorted(by: >) {
            array.remove(at: index)
        }

        var insertIndex = destination
        for index in source where index < destination {
            insertIndex -= 1
        }

        array.insert(contentsOf: moving, at: max(0, min(insertIndex, array.count)))
        return array
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case appearance
    case productivity
    case sync
    case integrations
    case advanced
    case developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .productivity: return "Productivity"
        case .sync: return "Sync"
        case .integrations: return "Integrations"
        case .advanced: return "Advanced"
        case .developer: return "Developer"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Core app preferences"
        case .appearance: return "Theme and top bar"
        case .productivity: return "Tasks, habits and focus"
        case .sync: return "Folder and backend sync"
        case .integrations: return "Calendar and coach"
        case .advanced: return "Optional power features"
        case .developer: return "Diagnostics and debug"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .productivity: return "bolt.fill"
        case .sync: return "arrow.triangle.2.circlepath"
        case .integrations: return "link"
        case .advanced: return "slider.horizontal.3"
        case .developer: return "terminal"
        }
    }
}

private struct SettingsCategoryCard: View {
    let category: SettingsCategory
    let selected: Bool
    let accent: Color
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? .white : .secondary)

                Text(category.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(category.subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(selected ? Color.white.opacity(0.82) : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .leading)
            .padding(14)
        }
        .buttonStyle(SettingsCategoryCardButtonStyle(selected: selected, hovering: hovering, accent: accent))
        .onHover { over in
            withAnimation(.easeOut(duration: 0.16)) {
                hovering = over
            }
        }
    }
}

private struct SettingsCategoryCardButtonStyle: ButtonStyle {
    let selected: Bool
    let hovering: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        return configuration.label
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(backgroundColor(pressed: pressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor(pressed: pressed), lineWidth: 1)
            )
            .scaleEffect(pressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.1), value: pressed)
            .animation(.easeOut(duration: 0.16), value: hovering)
            .animation(.easeOut(duration: 0.16), value: selected)
    }

    private func backgroundColor(pressed: Bool) -> Color {
        if selected {
            return accent.opacity(pressed ? 0.28 : 0.22)
        }
        if pressed {
            return Color.white.opacity(0.12)
        }
        if hovering {
            return Color.white.opacity(0.09)
        }
        return Color.white.opacity(0.055)
    }

    private func borderColor(pressed: Bool) -> Color {
        if selected {
            return accent.opacity(pressed ? 0.62 : 0.52)
        }
        if hovering {
            return Color.white.opacity(0.22)
        }
        return Color.white.opacity(0.12)
    }
}
