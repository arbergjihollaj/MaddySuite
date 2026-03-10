//
//  RootView.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI
import Combine
import AppKit

// =====================================================
// MARK: - RootView
// [TAG: V2_ROOT_VIEW]
// =====================================================

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var fileShelfStore: FileShelfStore
    @Environment(\.openWindow) private var openWindow

    @StateObject private var aiCommandRouter = AICommandRouter()
    @StateObject private var shellState = AppShellState()
    private let dateSyncTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var serialService: SerialService { appState.serialService }

    private var routeSelection: Binding<AppRoute?> {
        Binding<AppRoute?>(
            get: { appState.route },
            set: { selection in
                guard let selection else { return }
                appState.navigate(to: selection)
            }
        )
    }

    var body: some View {
        ZStack {
            MaddyBackground(accent: appState.accentColor)

            NavigationSplitView {
                sidebar
                    .frame(minWidth: 220)
            } detail: {
                mainDetail
            }
            .navigationSplitViewStyle(.balanced)

            if shellState.showAIQuickBar {
                AIQuickBarView(
                    isPresented: $shellState.showAIQuickBar,
                    onSubmitCommand: { input in
                        let result = aiCommandRouter.route(
                            command: input,
                            tasksViewModel: appState.tasksViewModel,
                            defaultPriority: appState.settings.taskDefaultPriority
                        )
                        if case .success = result {
                            appState.navigate(to: .tasks)
                        }
                        return result
                    },
                    onResolvePendingDate: { title, choice in
                        let result = aiCommandRouter.resolvePendingDate(
                            for: title,
                            choice: choice,
                            tasksViewModel: appState.tasksViewModel,
                            defaultPriority: appState.settings.taskDefaultPriority
                        )
                        if case .success = result {
                            appState.navigate(to: .tasks)
                        }
                        return result
                    }
                )
                .zIndex(20)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            VStack(spacing: 8) {
                if shellState.focusToastVisible {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Focus Complete")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.75))
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if shellState.dailySummaryVisible,
                   appState.settings.dailySummaryEnabled,
                   let summary = appState.gamificationService.dailySummaryText,
                   summary.isEmpty == false {
                    Text(summary)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: 420, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.78))
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarColorScheme(.dark, for: .windowToolbar)
        .onAppear {
            shellState.handleAppear(appState: appState, serialService: serialService)
            ensureShelfWindowVisibility()
        }
        .onReceive(dateSyncTimer) { _ in
            shellState.sendDateToESPIfConnected(serialService)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            ensureShelfWindowVisibility()
        }
        .onChange(of: fileShelfStore.items.count) { oldValue, newValue in
            if oldValue == 0, newValue > 0 {
                openWindow(id: FileShelfWindowID.panel)
            }
        }
        .onChange(of: serialService.isConnected) { _, connected in
            if connected {
                if appState.route == .ai {
                    serialService.sendAIStyle(appState.settings.aiPlaceholderStyle.rawValue)
                }
                shellState.sendDateToESPIfConnected(serialService)
            }
        }
        .onChange(of: appState.focusViewModel.logs.count) { _, newValue in
            shellState.handleFocusLogCountChange(newValue)
        }
        .onChange(of: appState.gamificationService.dailySummarySignal) { _, _ in
            shellState.showDailySummaryToastIfNeeded(appState)
        }
    }

    private var sidebar: some View {
        List(selection: routeSelection) {
            Section("Workspace") {
                ForEach(appState.topOrder) { route in
                    Label(route.title, systemImage: route.icon)
                        .tag(route as AppRoute?)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    private var mainDetail: some View {
        ZStack {
            switch appState.route {
            case .home:
                HomeView()
            case .calendar:
                MacCalendarView()
            case .focus:
                FocusView()
            case .tasks:
                TasksView()
            case .habits:
                HabitsView()
            case .gamify:
                GamificationView(
                    viewModel: GamificationViewModel(
                        service: appState.gamificationService,
                        accent: appState.accentColor
                    ),
                    accent: appState.accentColor
                )
            case .ai:
                AIView()
            case .settings:
                SettingsView()
            }
        }
        .padding(16)
        .animation(.easeInOut(duration: 0.22), value: appState.route)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionState.color)
                        .frame(width: 8, height: 8)
                    Text(connectionState.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        shellState.showAIQuickBar = true
                    }
                } label: {
                    Image(systemName: aiStatus.symbol)
                        .foregroundStyle(aiStatus.tint)
                }
                .help(aiStatus.accessibilityLabel)

                if appState.route != .settings {
                    Button {
                        appState.navigate(to: .settings)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Open Settings")
                }
            }
        }
    }

    private var connectionState: TitleBarConnectionState {
        if serialService.isConnected {
            return .connected
        }

        let status = serialService.status.lowercased()
        if status.contains("connect") || status.contains("reconnect") {
            return .reconnecting
        }

        if serialService.autoReconnectEnabled, serialService.selectedPort != nil {
            return .reconnecting
        }

        return .disconnected
    }

    private var aiStatus: TitleBarAIStatus {
        let aiService = appState.aiService
        if aiService.isRequestInFlight {
            return .thinking
        }

        switch aiService.status {
        case .local, .cloud:
            return .ready
        case .offline:
            return .offline
        }
    }

    // =====================================================
    // MARK: - File Shelf Window Sync
    // [TAG: FILE_SHELF_WINDOW_SYNC]
    // =====================================================
    private func ensureShelfWindowVisibility() {
        guard fileShelfStore.hasItems else { return }
        openWindow(id: FileShelfWindowID.panel)
    }
}
