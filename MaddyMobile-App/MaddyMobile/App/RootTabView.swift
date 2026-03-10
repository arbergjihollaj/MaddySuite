import SwiftUI

/// File: App/RootTabView.swift

// =====================================================
// MARK: - RootTabView
// [TAG: MOBILE_ROOT_TABS]
// =====================================================

struct RootTabView: View {
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var game: GamificationStore

    @State private var selectedTab: MobileTab = .home
    @State private var focusToastVisible = false
    @State private var dailySummaryVisible = false

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(settings.visibleTabs) { tab in
                tabDestination(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .tag(tab)
            }
        }
        .tint(.white)
        .background(AppTheme.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if focusToastVisible {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(focus.completionMessage ?? "Focus Complete")
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

                if dailySummaryVisible,
                   let summary = game.dailySummaryText,
                   summary.isEmpty == false {
                    Text(summary)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: 340, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.black.opacity(0.78))
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 10)
        }
        .onChange(of: focus.completionSignal) { _, _ in
            withAnimation(.easeInOut(duration: 0.22)) {
                focusToastVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    focusToastVisible = false
                }
            }
        }
        .onChange(of: game.dailySummarySignal) { _, _ in
            guard settings.dailySummaryEnabled else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                dailySummaryVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    dailySummaryVisible = false
                }
            }
        }
        .onAppear {
            ensureSelectedTabIsVisible()
        }
        .onChange(of: settings.visibleTabs) { _, _ in
            ensureSelectedTabIsVisible()
        }
    }

    @ViewBuilder
    private func tabDestination(for tab: MobileTab) -> some View {
        switch tab {
        case .home:
            NavigationStack { HomeView() }
        case .focus:
            NavigationStack { FocusView() }
        case .tasks:
            NavigationStack { TasksView() }
        case .habits:
            NavigationStack { HabitsView() }
        case .more:
            NavigationStack { MoreView() }
        }
    }

    private func ensureSelectedTabIsVisible() {
        if settings.visibleTabs.contains(selectedTab) == false {
            selectedTab = .home
        }
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
                CalendarView()
            } label: {
                Label("Calendar", systemImage: "calendar")
            }

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
