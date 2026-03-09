//
//  TitleBarView.swift
//  MaddyV2
//
//  Created by Codex on 04.03.26.
//

import SwiftUI

// =====================================================
// MARK: - Title Bar Models
// [TAG: V2_TITLEBAR_MODELS]
// =====================================================

enum TitleBarConnectionState {
    case connected
    case reconnecting
    case disconnected

    var color: Color {
        switch self {
        case .connected: return .green
        case .reconnecting: return .orange
        case .disconnected: return .red
        }
    }

    var label: String {
        switch self {
        case .connected: return "ESP Connected"
        case .reconnecting: return "Reconnecting"
        case .disconnected: return "Disconnected"
        }
    }
}

enum TitleBarAIStatus {
    case ready
    case thinking
    case offline

    var symbol: String {
        switch self {
        case .ready: return "sparkles"
        case .thinking: return "ellipsis.message.fill"
        case .offline: return "bolt.slash.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready: return .white
        case .thinking: return .orange
        case .offline: return .secondary
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .ready: return "AI Ready"
        case .thinking: return "AI Thinking"
        case .offline: return "AI Offline"
        }
    }
}

// =====================================================
// MARK: - Title Bar View
// [TAG: V2_TITLEBAR_VIEW]
// =====================================================

struct TitleBarView: View {
    @EnvironmentObject private var appState: AppState

    let currentRoute: AppRoute
    let connectionState: TitleBarConnectionState
    private let aiStatus: TitleBarAIStatus
    let aiQuickAction: () -> Void
    let settingsAction: () -> Void

    init(
        currentRoute: AppRoute,
        connectionState: TitleBarConnectionState,
        AIStatus: TitleBarAIStatus,
        aiQuickAction: @escaping () -> Void,
        settingsAction: @escaping () -> Void
    ) {
        self.currentRoute = currentRoute
        self.connectionState = connectionState
        self.aiStatus = AIStatus
        self.aiQuickAction = aiQuickAction
        self.settingsAction = settingsAction
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(appState.accentColor)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )

                Text(currentRoute.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Image(systemName: currentRoute.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(currentRoute.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionState.color)
                        .frame(width: 8, height: 8)
                    Text(connectionState.label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )

                TitleBarIconButton(
                    symbol: aiStatus.symbol,
                    tint: aiStatus.tint,
                    accessibilityLabel: aiStatus.accessibilityLabel
                ) {
                    aiQuickAction()
                }

                TitleBarIconButton(
                    symbol: "gearshape.fill",
                    tint: .white,
                    accessibilityLabel: "Open Settings",
                    action: settingsAction
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.6)
                .padding(.horizontal, 8)
        }
    }
}

private struct TitleBarIconButton: View {
    let symbol: String
    let tint: Color
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isHovering ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(isHovering ? 0.25 : 0.12), lineWidth: 0.8)
                }
                .animation(.easeInOut(duration: 0.16), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(accessibilityLabel)
    }
}
