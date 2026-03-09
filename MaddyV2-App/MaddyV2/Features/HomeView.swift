//
//  HomeView.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI

// =====================================================
// MARK: - HomeView
// [TAG: V2_HOME_VIEW]
// =====================================================

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var serialService: SerialService
    @EnvironmentObject var musicService: MusicService
    @EnvironmentObject var fileShelfStore: FileShelfStore
    @Environment(\.openWindow) private var openWindow
    @State private var isExportingExcel = false
    @State private var exportToastText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                quickNavigation
                widgetGrid
                serialControls
            }
            .padding(.bottom, 10)
        }
    }

    private var quickNavigation: some View {
        GlassCard(title: "Quick Navigation", accent: appState.accentColor) {
            HStack(spacing: 10) {
                quickRouteButton(.focus)
                quickRouteButton(.tasks)
                quickRouteButton(.habits)
                quickRouteButton(.music)
            }
        }
    }

    private var widgetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(appState.settings.homeWidgets) { widget in
                widgetCard(widget)
            }
        }
    }

    private var serialControls: some View {
        GlassCard(title: "ESP Connection", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Picker("Port", selection: Binding(
                        get: { serialService.selectedPort ?? "" },
                        set: { serialService.selectedPort = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("No Port").tag("")
                        ForEach(serialService.availablePorts, id: \.self) { port in
                            Text(port).tag(port)
                        }
                    }
                    .frame(maxWidth: 220, alignment: .leading)
                    .pickerStyle(.menu)
                    .labelsHidden()

                    HStack(spacing: 8) {
                        connectionIconButton(
                            symbol: "arrow.clockwise",
                            label: "Refresh ports",
                            enabled: true
                        ) {
                            serialService.refreshPorts()
                        }

                        connectionIconButton(
                            symbol: "link",
                            label: "Connect",
                            enabled: serialService.selectedPort != nil
                        ) {
                            serialService.connect()
                        }

                        connectionIconButton(
                            symbol: "link.slash",
                            label: "Disconnect",
                            enabled: serialService.isConnected
                        ) {
                            serialService.disconnect()
                        }
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(serialService.isConnected ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(serialService.status)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                }

                HStack {
                    Button {
                        openWindow(id: FileShelfWindowID.panel)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: fileShelfStore.hasItems ? "tray.full.fill" : "tray")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Open Shelf")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                                }
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    // =====================================================
                    // MARK: - Home Excel Button
                    // [TAG: V2_HOME_EXCEL_BUTTON]
                    // =====================================================
                    Button {
                        Task {
                            isExportingExcel = true
                            let success = await appState.exportStatisticsNow()
                            isExportingExcel = false
                            showExportToast(success ? "Excel updated ✓" : "Export failed")
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isExportingExcel ? "arrow.triangle.2.circlepath" : "tablecells.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text(isExportingExcel ? "Updating..." : "Update Excel")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(appState.accentColor.opacity(0.24))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                                }
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isExportingExcel)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let exportToastText {
                Text(exportToastText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(0.65))
                    )
                    .padding(.trailing, 10)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: exportToastText)
    }

    private func connectionIconButton(
        symbol: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HomeConnectionIconButton(
            symbol: symbol,
            label: label,
            tint: appState.accentColor,
            enabled: enabled,
            action: action
        )
    }

    // =====================================================
    // MARK: - Home Toast
    // [TAG: V2_HOME_EXCEL_TOAST]
    // =====================================================
    private func showExportToast(_ message: String) {
        withAnimation {
            exportToastText = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                exportToastText = nil
            }
        }
    }

    private func quickRouteButton(_ route: AppRoute) -> some View {
        Button {
            appState.navigate(to: route)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: route.icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(route.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(appState.accentColor.opacity(0.22))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func widgetCard(_ widget: HomeWidgetKind) -> some View {
        switch widget {
        case .focus:
            GlassCard(title: "Focus", accent: appState.accentColor) {
                HStack {
                    StatChip(label: "Today", value: "\(appState.focusViewModel.todaySessions)", accent: appState.accentColor)
                    StatChip(label: "Streak", value: "\(appState.focusViewModel.streakDays)d", accent: appState.accentColor)
                }
            }
        case .tasks:
            GlassCard(title: "Tasks", accent: appState.accentColor) {
                let backlog = appState.tasksViewModel.tasks(for: .backlog).count
                let inProgress = appState.tasksViewModel.tasks(for: .inProgress).count
                let done = appState.tasksViewModel.tasks(for: .done).count

                HStack {
                    StatChip(label: "Backlog", value: "\(backlog)", accent: appState.accentColor)
                    StatChip(label: "In Progress", value: "\(inProgress)", accent: appState.accentColor)
                    StatChip(label: "Done", value: "\(done)", accent: appState.accentColor)
                }
            }
        case .habits:
            GlassCard(title: "Habits", accent: appState.accentColor) {
                let weeklyScore = appState.habitsViewModel.weeklyCompletionCount()
                Text("Weekly completion score: \(weeklyScore)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
        case .music:
            GlassCard(title: "Music", accent: appState.accentColor) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(musicService.snapshot.title.isEmpty ? "No current track" : musicService.snapshot.title)
                        .lineLimit(1)
                    Text(musicService.snapshot.artist)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView(value: musicService.snapshot.progress)
                        .tint(appState.accentColor)
                }
            }
        case .serial:
            GlassCard(title: "Serial", accent: appState.accentColor) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(serialService.isConnected ? "Connected" : "Disconnected")
                        .foregroundStyle(serialService.isConnected ? .green : .orange)
                    Text("Firmware: \(serialService.firmwareVersion)")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
            }
        }
    }
}

private struct HomeConnectionIconButton: View {
    let symbol: String
    let label: String
    let tint: Color
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(
            HomeConnectionIconButtonStyle(
                tint: tint,
                hovering: hovering,
                enabled: enabled
            )
        )
        .disabled(enabled == false)
        .accessibilityLabel(Text(label))
        .help(label)
        .onHover { over in
            withAnimation(.easeOut(duration: 0.14)) {
                hovering = over
            }
        }
    }
}

private struct HomeConnectionIconButtonStyle: ButtonStyle {
    let tint: Color
    let hovering: Bool
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        return configuration.label
            .foregroundStyle(enabled ? Color.white : Color.secondary.opacity(0.75))
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(backgroundColor(pressed: pressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(borderColor(pressed: pressed), lineWidth: 0.9)
            )
            .scaleEffect(pressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: pressed)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .animation(.easeOut(duration: 0.14), value: enabled)
    }

    private func backgroundColor(pressed: Bool) -> Color {
        guard enabled else { return Color.white.opacity(0.03) }
        if pressed { return tint.opacity(0.22) }
        if hovering { return Color.white.opacity(0.12) }
        return Color.white.opacity(0.07)
    }

    private func borderColor(pressed: Bool) -> Color {
        guard enabled else { return Color.white.opacity(0.07) }
        if pressed { return tint.opacity(0.5) }
        if hovering { return Color.white.opacity(0.23) }
        return Color.white.opacity(0.14)
    }
}
