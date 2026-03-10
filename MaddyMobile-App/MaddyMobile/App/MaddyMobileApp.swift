import SwiftUI

/// File: App/MaddyMobileApp.swift

// =====================================================
// MARK: - MaddyMobileApp
// [TAG: MOBILE_APP_ENTRY]
// =====================================================

@main
struct MaddyMobileApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(appModel)
                .environmentObject(appModel.settingsStore)
                .environmentObject(appModel.tasksStore)
                .environmentObject(appModel.habitStore)
                .environmentObject(appModel.focusStore)
                .environmentObject(appModel.gamificationStore)
                .environmentObject(appModel.calendarStore)
                .preferredColorScheme(.dark)
        }
    }
}
