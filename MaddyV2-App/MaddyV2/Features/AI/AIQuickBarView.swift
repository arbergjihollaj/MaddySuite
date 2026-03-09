//
//  AIQuickBarView.swift
//  MaddyV2
//
//  Created by Codex on 04.03.26.
//

import SwiftUI

// =====================================================
// MARK: - AI Quick Bar View
// [TAG: V2_AI_QUICK_BAR]
// =====================================================

struct AIQuickBarView: View {
    @Binding var isPresented: Bool

    let onSubmitCommand: (String) -> AICommandRouter.RouteResult
    let onResolvePendingDate: (String, AICommandRouter.PendingDueChoice) -> AICommandRouter.RouteResult

    @State private var commandText: String = ""
    @State private var feedbackText: String = "Ask Maddy to create a task."
    @State private var feedbackColor: Color = .secondary
    @State private var pendingTitle: String?

    @FocusState private var commandFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    close()
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.white.opacity(0.85))
                    TextField("Ask Maddy…", text: $commandText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .focused($commandFocused)
                        .onSubmit {
                            submit()
                        }

                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

                if let pendingTitle, pendingTitle.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Set due date?")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))

                        HStack(spacing: 8) {
                            quickDateButton("Today", choice: .today, title: pendingTitle)
                            quickDateButton("Tomorrow", choice: .tomorrow, title: pendingTitle)
                            quickDateButton("Next Week", choice: .nextWeek, title: pendingTitle)
                            quickDateButton("No Date", choice: .none, title: pendingTitle)
                        }
                    }
                }

                Text(feedbackText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(feedbackColor)

                Text("Examples: create task Essay due 2026-03-10 · ich muss bis zum nächsten Mittwoch die Mathe Hausaufgaben erledigen")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(width: 720)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    }
            )
            .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
        }
        .onAppear {
            commandFocused = true
        }
        .onExitCommand {
            close()
        }
    }

    private func quickDateButton(_ title: String, choice: AICommandRouter.PendingDueChoice, title pendingTitle: String) -> some View {
        Button(title) {
            handleResult(onResolvePendingDate(pendingTitle, choice))
        }
        .buttonStyle(.bordered)
    }

    private func submit() {
        handleResult(onSubmitCommand(commandText))
    }

    private func handleResult(_ result: AICommandRouter.RouteResult) {
        switch result {
        case .success(let message):
            feedbackText = message
            feedbackColor = .green
            pendingTitle = nil
            commandText = ""

        case .needsDateConfirmation(let title):
            pendingTitle = title
            feedbackText = "Could not parse due date automatically."
            feedbackColor = .orange

        case .failure(let message):
            feedbackText = message
            feedbackColor = .orange
            pendingTitle = nil
        }
    }

    private func close() {
        isPresented = false
        pendingTitle = nil
    }
}
