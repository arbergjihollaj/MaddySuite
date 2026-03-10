//
//  AppShellState.swift
//  MaddyV2
//
//  Feature-scoped UI state for RootView shell interactions.
//

import SwiftUI
import Combine

@MainActor
final class AppShellState: ObservableObject {
    @Published var showAIQuickBar = false
    @Published var focusToastVisible = false
    @Published var dailySummaryVisible = false

    private var lastFocusLogCount = 0

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func handleAppear(appState: AppState, serialService: SerialService) {
        serialService.sendView(screen: appState.route.rawValue)
        if appState.route == .ai {
            serialService.sendAIStyle(appState.settings.aiPlaceholderStyle.rawValue)
        }
        sendDateToESPIfConnected(serialService)
        lastFocusLogCount = appState.focusViewModel.logs.count
    }

    func sendDateToESPIfConnected(_ serialService: SerialService) {
        guard serialService.isConnected else { return }
        let now = Date()
        serialService.sendTime(Self.timeFormatter.string(from: now))
        _ = serialService.sendLine("date:\(Self.dateFormatter.string(from: now))")
    }

    func handleFocusLogCountChange(_ newValue: Int) {
        guard newValue > lastFocusLogCount else { return }
        lastFocusLogCount = newValue

        withAnimation(.easeInOut(duration: 0.22)) {
            focusToastVisible = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.focusToastVisible = false
            }
        }
    }

    func showDailySummaryToastIfNeeded(_ appState: AppState) {
        guard appState.settings.dailySummaryEnabled else { return }

        withAnimation(.easeInOut(duration: 0.22)) {
            dailySummaryVisible = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.dailySummaryVisible = false
            }
        }
    }
}
