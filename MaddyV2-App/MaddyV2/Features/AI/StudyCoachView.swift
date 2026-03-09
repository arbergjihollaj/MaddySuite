//
//  StudyCoachView.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI

// =====================================================
// MARK: - StudyCoachView
// [TAG: V2_AI_STUDY_VIEW]
// =====================================================

struct StudyCoachView: View {
    @EnvironmentObject var appState: AppState

    @State private var topicText: String = ""
    @State private var notesText: String = ""
    @State private var promptText: String = ""
    @State private var quizAnswerText: String = ""

    private var ai: AIService { appState.aiService }

    var body: some View {
        VStack(spacing: 10) {
            inputsCard
            actionsCard
            outputSections
            conversation
            quizPanel
            inputBar
        }
    }

    private var inputsCard: some View {
        VStack(spacing: 8) {
            TextField("Topic (e.g. Photosynthesis, Linear Algebra)", text: $topicText)
                .textFieldStyle(.roundedBorder)

            TextField("My notes (optional)", text: $notesText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)

            HStack {
                Picker("Language", selection: Binding(
                    get: { ai.memory.preferredLanguage },
                    set: { ai.setPreferredLanguage($0) }
                )) {
                    ForEach(AILanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.segmented)

                Spacer(minLength: 0)

                if ai.isQuizSessionActive {
                    Button("End Quiz") {
                        ai.endQuizSession()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var actionsCard: some View {
        HStack(spacing: 8) {
            ForEach(StudyCoachAction.allCases) { action in
                Button(action.title) {
                    ai.runStudyAction(action, topic: topicText, notes: notesText)
                }
                .buttonStyle(.bordered)
                .tint(action == .examSummary ? appState.accentColor : nil)
                .disabled(ai.isRequestInFlight)
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
    }

    private var outputSections: some View {
        let text = latestAssistantText

        return VStack(spacing: 8) {
            StudySectionCard(title: "Key points", items: extractSection("Key points", from: text), accent: appState.accentColor)
            StudySectionCard(title: "Definitions", items: extractSection("Definitions", from: text), accent: appState.accentColor)
            StudySectionCard(title: "Examples", items: extractSection("Examples", from: text), accent: appState.accentColor)
            StudySectionCard(title: "Quiz questions", items: extractSection("Quiz questions", from: text), accent: appState.accentColor)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if ai.messages(for: .study).isEmpty {
                        Text("Use an action above to get a structured study response.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }

                    ForEach(ai.messages(for: .study)) { message in
                        StudyCoachBubble(message: message, accent: appState.accentColor)
                            .id(message.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 220, maxHeight: 360)
            .onChange(of: ai.messages(for: .study).count) { _, _ in
                if let lastID = ai.messages(for: .study).last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var quizPanel: some View {
        if ai.isQuizSessionActive {
            VStack(alignment: .leading, spacing: 8) {
                if ai.awaitingQuizAnswer {
                    Text("Quiz mode: answer the current question.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Your answer", text: $quizAnswerText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)

                        Button("Submit") {
                            ai.submitQuizAnswer(quizAnswerText)
                            quizAnswerText = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(appState.accentColor)
                        .disabled(quizAnswerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ai.isRequestInFlight)
                    }
                }

                if ai.awaitingQuizEvaluation {
                    HStack(spacing: 10) {
                        Text("Was your answer correct?")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Button("Correct (+15 XP)") {
                            ai.markQuizAnswer(correct: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        Button("Not yet") {
                            ai.markQuizAnswer(correct: false)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Ask a follow-up question...", text: $promptText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit(send)

                if ai.isRequestInFlight {
                    Button("Stop") {
                        ai.cancelCurrentRequest()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Send") {
                    send()
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.accentColor)
                .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ai.isRequestInFlight)
            }

            HStack(spacing: 10) {
                Picker("Model", selection: Binding(
                    get: { ai.activeModelName },
                    set: { ai.updateActiveModelName($0) }
                )) {
                    ForEach(ai.activeModelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Use Cloud", isOn: Binding(
                    get: { ai.settings.useCloudForCurrentSession },
                    set: { ai.settings.useCloudForCurrentSession = $0 }
                ))
                .toggleStyle(.switch)

                Spacer()

                Button("Clear Chat") {
                    ai.clearChat(for: .study)
                }
                .buttonStyle(.bordered)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var latestAssistantText: String {
        ai.messages(for: .study)
            .last(where: { $0.role == .assistant })?
            .content ?? ""
    }

    private func send() {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        ai.sendStudyMessage(trimmed)
        promptText = ""
    }

    private func extractSection(_ header: String, from text: String) -> [String] {
        guard text.isEmpty == false else { return [] }

        let lines = text.components(separatedBy: .newlines)
        var capture = false
        var values: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if trimmed.lowercased().hasPrefix(header.lowercased()) {
                capture = true
                continue
            }

            if capture, trimmed.hasSuffix(":") {
                break
            }

            if capture {
                let cleaned = trimmed
                    .replacingOccurrences(of: "- ", with: "")
                    .replacingOccurrences(of: "• ", with: "")
                values.append(cleaned)
            }
        }

        return Array(values.prefix(4))
    }
}

// =====================================================
// MARK: - Supporting Views
// [TAG: V2_AI_STUDY_SUPPORT]
// =====================================================

private struct StudyCoachBubble: View {
    let message: AIMessage
    let accent: Color

    var body: some View {
        HStack {
            if message.role == .assistant {
                content(fill: Color.white.opacity(0.06), alignment: .leading)
                Spacer(minLength: 22)
            } else {
                Spacer(minLength: 22)
                content(fill: accent.opacity(0.22), alignment: .trailing)
            }
        }
    }

    private func content(fill: Color, alignment: Alignment) -> some View {
        Text(message.content.isEmpty ? "..." : message.content)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .textSelection(.enabled)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 700, alignment: alignment)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill)
            )
    }
}

private struct StudySectionCard: View {
    let title: String
    let items: [String]
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)

            if items.isEmpty {
                Text("Waiting for content...")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}
