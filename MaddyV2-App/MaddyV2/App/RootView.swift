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
    @EnvironmentObject var serialService: SerialService
    @EnvironmentObject var musicService: MusicService
    @EnvironmentObject var fileShelfStore: FileShelfStore
    @Environment(\.openWindow) private var openWindow

    @StateObject private var aiCommandRouter = AICommandRouter()
    @State private var showAIQuickBar = false
    private let dateSyncTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

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
                            showAIQuickBar = true
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
                    case .music:
                        MusicView()
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

            if showAIQuickBar {
                AIQuickBarView(
                    isPresented: $showAIQuickBar,
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
        }
        .preferredColorScheme(.dark)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarColorScheme(.dark, for: .windowToolbar)
        .onAppear {
            serialService.sendView(screen: appState.route.rawValue)
            if appState.route == .ai {
                serialService.sendAIStyle(appState.settings.aiPlaceholderStyle.rawValue)
            }
            sendDateToESPIfConnected()
            ensureShelfWindowVisibility()
        }
        .onReceive(dateSyncTimer) { _ in
            sendDateToESPIfConnected()
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
                sendDateToESPIfConnected()
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

    private func sendDateToESPIfConnected() {
        guard serialService.isConnected else { return }

        let now = Date()
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        serialService.sendTime(timeFormatter.string(from: now))
        _ = serialService.sendLine("date:\(dateFormatter.string(from: now))")
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
