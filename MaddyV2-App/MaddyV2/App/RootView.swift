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

    var body: some View {
        ZStack {
            MaddyBackground(accent: appState.accentColor)

            VStack(spacing: 12) {
                TitleBarView(
                    currentRoute: appState.route,
                    connectionState: connectionState,
                    AIStatus: aiStatus,
                    aiQuickAction: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            shellState.showAIQuickBar = true
                        }
                    }
                ) {
                    appState.navigate(to: .settings)
                }

                ZStack {
                    switch appState.route {
                    case .home:
                        HomeView()
                            .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
                    case .calendar:
                        MacCalendarView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    case .focus:
                        FocusView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    case .tasks:
                        TasksView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    case .habits:
                        HabitsView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    case .gamify:
                        GamificationView(
                            viewModel: GamificationViewModel(
                                service: appState.gamificationService,
                                accent: appState.accentColor
                            ),
                            accent: appState.accentColor
                        )
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    case .ai:
                        AIView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    case .settings:
                        SettingsView()
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.28), value: appState.route)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                BottomNavigationBar()
            }
            .padding(16)

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
