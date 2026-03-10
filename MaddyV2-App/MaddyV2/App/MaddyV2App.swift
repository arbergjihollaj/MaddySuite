//
//  MaddyV2App.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI

@main
struct MaddyV2App: App {
    @StateObject private var serialService: SerialService
    @StateObject private var appState: AppState
    @StateObject private var fileShelfStore: FileShelfStore

    init() {
        let serial = SerialService()
        let shelf = FileShelfStore()

        _serialService = StateObject(wrappedValue: serial)
        _appState = StateObject(wrappedValue: AppState(serialService: serial))
        _fileShelfStore = StateObject(wrappedValue: shelf)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(serialService)
                .environmentObject(fileShelfStore)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1240, height: 820)

        Window("File Shelf", id: FileShelfWindowID.panel) {
            FileShelfPanelView()
                .environmentObject(appState)
                .environmentObject(fileShelfStore)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 430, height: 280)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("MaddyV2", systemImage: "sparkles") {
            if appState.settings.menuBarEnabled {
                MenuBarPanelView()
                    .environmentObject(appState)
                    .environmentObject(serialService)
                    .environmentObject(fileShelfStore)
                    .frame(width: 320)
                    .padding(12)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Menu Bar mode is disabled in Settings.")
                    Button("Open Settings") {
                        appState.navigate(to: .settings)
                    }
                }
                .padding(12)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(serialService)
                .environmentObject(fileShelfStore)
                .frame(width: 900, height: 680)
        }
    }
}

// =====================================================
// MARK: - Menu Bar
// [TAG: V2_MENU_BAR]
// =====================================================

private struct MenuBarPanelView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var serialService: SerialService
    @EnvironmentObject var fileShelfStore: FileShelfStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MaddyV2")
                .font(.system(size: 18, weight: .bold, design: .rounded))

            HStack {
                Circle()
                    .fill(serialService.isConnected ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(serialService.isConnected ? "ESP Connected" : "ESP Disconnected")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }

            HStack(spacing: 8) {
                ForEach([AppRoute.home, .focus, .tasks, .habits]) { route in
                    Button(route.title) {
                        appState.navigate(to: route)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Divider()

            Button {
                openWindow(id: FileShelfWindowID.panel)
            } label: {
                Label("Open File Shelf", systemImage: fileShelfStore.hasItems ? "tray.full.fill" : "tray")
            }
            .buttonStyle(.bordered)
        }
    }
}
