//
//  AIToolsPanel.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI

// =====================================================
// MARK: - AIToolsPanel
// [TAG: V2_AI_TOOLS_PANEL]
// =====================================================

struct AIToolsPanel: View {
    let accent: Color
    var onAction: (AIQuickAction) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(AIQuickAction.allCases) { action in
                Button {
                    onAction(action)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(action.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        Text(caption(for: action))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(accent.opacity(0.35), lineWidth: 0.8)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func caption(for action: AIQuickAction) -> String {
        switch action {
        case .explainConcept: return "Break down difficult ideas"
        case .makeFlashcards: return "Generate Q/A cards"
        case .generateQuiz: return "Create practice questions"
        case .summarizeNotes: return "Compress your notes"
        case .planStudySession: return "Build a 25/50 min study plan"
        }
    }
}
