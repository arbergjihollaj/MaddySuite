import SwiftUI

/// File: App/RootTabView.swift

// =====================================================
// MARK: - RootTabView
// [TAG: MOBILE_ROOT_TABS]
// =====================================================

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack {
                FocusView()
            }
            .tabItem {
                Label("Focus", systemImage: "timer")
            }

            NavigationStack {
                TasksView()
            }
            .tabItem {
                Label("Tasks", systemImage: "checklist")
            }

            NavigationStack {
                HabitsView()
            }
            .tabItem {
                Label("Habits", systemImage: "flame")
            }

            NavigationStack {
                MoreView()
            }
            .tabItem {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        .tint(.white)
        .background(AppTheme.background.ignoresSafeArea())
    }
}

// =====================================================
// MARK: - MoreView
// [TAG: MOBILE_MORE_TAB]
// =====================================================

private struct MoreView: View {
    var body: some View {
        List {
            NavigationLink {
                GamificationView()
            } label: {
                Label("Gamification", systemImage: "hexagon")
            }

            NavigationLink {
                StatsView()
            } label: {
                Label("Stats", systemImage: "chart.bar")
            }

            NavigationLink {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("More")
    }
}
