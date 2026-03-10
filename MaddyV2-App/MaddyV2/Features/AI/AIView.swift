//
//  AIView.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI

// =====================================================
// MARK: - AIView
// [TAG: V2_AI_MAIN_VIEW]
// =====================================================

struct AIView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("maddy.ai.showQuickActions") private var aiShowQuickActions: Bool = true
    @AppStorage("maddy.ai.showDailyChallenge") private var aiShowDailyChallenge: Bool = true
    @AppStorage("maddy.ai.showToolStrip") private var aiShowToolStrip: Bool = true
    @State private var showAdvancedControls = false

    private var ai: AIService { appState.aiService }

    var body: some View {
        Group {
            if ai.mode == .chat {
                VStack(spacing: 14) {
                    topCards
                    contentCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.bottom, 10)
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        topCards
                        contentCard
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .overlay(alignment: .top) {
            if let toast = ai.xpToastText, toast.isEmpty == false {
                Text(toast)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule(style: .continuous)
                            .fill(appState.accentColor.opacity(0.8))
                    )
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: ai.xpToastToken)
        .onAppear {
            if appState.serialService.isConnected {
                appState.serialService.sendView(screen: "coach")
                appState.serialService.sendAIStyle(appState.settings.aiPlaceholderStyle.rawValue)
            }
        }
    }

    @ViewBuilder
    private var topCards: some View {
        headerCard
        if aiShowQuickActions {
            quickActionsCard
        }
        if aiShowDailyChallenge {
            dailyChallengeCard
        }
    }

    private var headerCard: some View {
        GlassCard(title: "Study Coach AI", accent: appState.accentColor) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Picker("Mode", selection: Binding(
                        get: { ai.mode },
                        set: { ai.mode = $0 }
                    )) {
                        ForEach(AIConversationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }

                HStack(spacing: 10) {
                    statusChip

                    if ai.hasNotes {
                        Text("Notes \(ai.noteCount)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Use Notes", isOn: Binding(
                        get: { ai.memory.useNotesForAnswers },
                        set: { ai.setUseNotesForAnswers($0) }
                    ))
                    .toggleStyle(.switch)
                    .font(.system(size: 11, weight: .medium, design: .rounded))

                    Spacer(minLength: 0)
                }

                if aiShowToolStrip {
                    DisclosureGroup("Advanced controls", isExpanded: $showAdvancedControls) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(ai.orderedTools) { tool in
                                    Button {
                                        ai.runCoachTool(tool)
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: tool.icon)
                                                .font(.system(size: 10, weight: .semibold))
                                            Text(tool.title)
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        }
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(Color.white.opacity(0.08))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                }

                if let fallback = ai.providerFallbackNotice, fallback.isEmpty == false {
                    Text(fallback)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error = ai.lastErrorMessage, error.isEmpty == false {
                    Text(error)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var quickActionsCard: some View {
        GlassCard(title: "Quick Actions", accent: appState.accentColor) {
            AIToolsPanel(accent: appState.accentColor) { action in
                ai.runQuickAction(action, userContext: "")
            }
        }
    }

    private var dailyChallengeCard: some View {
        GlassCard(title: "Daily Study Challenge", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 8) {
                Text(ai.dailyChallengePrompt)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))

                HStack(spacing: 8) {
                    Image(systemName: ai.dailyChallengeCompleted ? "checkmark.seal.fill" : "target")
                        .foregroundStyle(ai.dailyChallengeCompleted ? .green : .secondary)
                    Text(ai.dailyChallengeProgressText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var contentCard: some View {
        GlassCard(accent: appState.accentColor) {
            Group {
                switch ai.mode {
                case .study:
                    StudyCoachView()
                case .chat:
                    AIChatView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .environmentObject(appState)
            .animation(.easeInOut(duration: 0.2), value: ai.mode)
        }
    }

    private var statusChip: some View {
        let color: Color = {
            if ai.providerStatus.hasPrefix("Local") { return .green }
            if ai.providerStatus == "Cloud" { return appState.accentColor }
            return .orange
        }()

        return HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(ai.providerStatus)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}
