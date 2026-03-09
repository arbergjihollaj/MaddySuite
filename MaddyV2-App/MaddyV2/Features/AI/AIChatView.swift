//
//  AIChatView.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI

// =====================================================
// MARK: - AIChatView
// [TAG: V2_AI_CHAT_VIEW]
// =====================================================

struct AIChatView: View {
    @EnvironmentObject var appState: AppState

    @State private var inputText: String = ""

    private var ai: AIService { appState.aiService }

    var body: some View {
        VStack(spacing: 0) {
            conversation
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
                .opacity(0.18)

            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if ai.messages(for: .chat).isEmpty {
                        Text("Start a conversation with Coach AI.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.top, 14)
                    }

                    ForEach(ai.messages(for: .chat)) { message in
                        ChatBubble(
                            message: message,
                            accent: appState.accentColor
                        )
                        .id(message.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .frame(minHeight: 240, maxHeight: .infinity)
            .onChange(of: ai.messages(for: .chat).count) { _, _ in
                if let lastID = ai.messages(for: .chat).last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Ask Coach AI...", text: $inputText, axis: .vertical)
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
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ai.isRequestInFlight)
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
                    ai.clearChat(for: .chat)
                }
                .buttonStyle(.bordered)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.top, 8)
    }

    private func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        ai.sendChatMessage(trimmed)
        inputText = ""
    }
}

// =====================================================
// MARK: - Bubble
// [TAG: V2_AI_CHAT_BUBBLE]
// =====================================================

private struct ChatBubble: View {
    let message: AIMessage
    let accent: Color

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble(alignment: .leading, fill: Color.white.opacity(0.06))
                Spacer(minLength: 24)
            } else {
                Spacer(minLength: 24)
                bubble(alignment: .trailing, fill: accent.opacity(0.22))
            }
        }
    }

    private func bubble(alignment: Alignment, fill: Color) -> some View {
        Text(message.content.isEmpty ? "..." : message.content)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .textSelection(.enabled)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 720, alignment: alignment)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill)
            )
    }
}
