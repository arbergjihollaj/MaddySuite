//
//  AISettingsView.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// =====================================================
// MARK: - AISettingsView
// [TAG: V2_AI_SETTINGS_VIEW]
// =====================================================

struct AISettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var ai: AIService

    @State private var apiKeyDraft: String = ""
    @State private var topicsDraft: String = ""
    @State private var weakTopicsDraft: String = ""
    @State private var coachNotesDraft: String = ""
    @State private var notesDraft: String = ""

    init(ai: AIService) {
        self.ai = ai
    }

    var body: some View {
        GlassCard(title: "AI", accent: appState.accentColor) {
            VStack(alignment: .leading, spacing: 12) {
                coachStyleSection
                Divider()
                localSection
                Divider()
                cloudSection
                Divider()
                notesSection
                Divider()
                debugSection
            }
        }
        .onAppear(perform: syncDrafts)
    }

    // =====================================================
    // MARK: - Coach Style
    // =====================================================

    private var coachStyleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Coach Style")

            Picker("Language", selection: Binding(
                get: { ai.memory.preferredLanguage },
                set: { ai.setPreferredLanguage($0) }
            )) {
                ForEach(AILanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Picker("Verbosity", selection: Binding(
                    get: { ai.memory.verbosity },
                    set: { ai.setVerbosity($0) }
                )) {
                    ForEach(AIMemoryVerbosity.allCases) { verbosity in
                        Text(verbosity.title).tag(verbosity)
                    }
                }
                .pickerStyle(.menu)

                Picker("Strictness", selection: Binding(
                    get: { ai.memory.coachingStrictness },
                    set: { ai.setStrictness($0) }
                )) {
                    ForEach(AICoachingStrictness.allCases) { strictness in
                        Text(strictness.title).tag(strictness)
                    }
                }
                .pickerStyle(.menu)

                Picker("Default Tool", selection: Binding(
                    get: { ai.memory.defaultStudyTool },
                    set: { ai.setDefaultTool($0) }
                )) {
                    ForEach(AICoachTool.allCases) { tool in
                        Text(tool.title).tag(tool)
                    }
                }
                .pickerStyle(.menu)
            }

            TextField("Preferred topics (comma separated)", text: Binding(
                get: { topicsDraft },
                set: { topicsDraft = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            TextField("Weak topics (comma separated)", text: Binding(
                get: { weakTopicsDraft },
                set: { weakTopicsDraft = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Personal coach notes")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                TextEditor(text: Binding(
                    get: { coachNotesDraft },
                    set: { coachNotesDraft = $0 }
                ))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 76)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                    )
            }

            Button("Save Coach Profile") {
                ai.updateTopicsCSV(topicsDraft)
                ai.updateWeakTopicsCSV(weakTopicsDraft)
                ai.updatePersonalCoachNotes(coachNotesDraft)
                syncDrafts()
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Tool order")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Drag to reorder")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                List {
                    ForEach(ai.orderedTools) { tool in
                        HStack {
                            Label(tool.title, systemImage: tool.icon)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                            Spacer()
                            if tool == ai.memory.defaultStudyTool {
                                Text("Default")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(appState.accentColor)
                            }
                        }
                    }
                    .onMove(perform: ai.moveToolOrder)
                }
                .frame(height: 156)
                .listStyle(.inset)
            }
        }
    }

    // =====================================================
    // MARK: - Local AI
    // =====================================================

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Local AI")

            Picker("Provider", selection: Binding(
                get: { ai.settings.localProvider },
                set: { provider in
                    ai.settings.localProvider = provider
                    if ai.settings.localBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ai.settings.localBaseURL = defaultBaseURL(for: provider)
                    }
                }
            )) {
                ForEach(AILocalProvider.allCases) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            TextField("Local Base URL", text: Binding(
                get: { ai.settings.localBaseURL },
                set: { ai.settings.localBaseURL = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            TextField("Local Model", text: Binding(
                get: { ai.settings.localModelName },
                set: { ai.settings.localModelName = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            HStack {
                Button("Test Local") {
                    ai.testLocalConnection()
                }
                .buttonStyle(.bordered)

                if let message = ai.localTestMessage, message.isEmpty == false {
                    Text(message)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
    }

    // =====================================================
    // MARK: - Cloud AI
    // =====================================================

    private var cloudSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Cloud AI")

            Toggle("Enable Cloud", isOn: Binding(
                get: { ai.settings.cloudEnabled },
                set: { ai.setCloudEnabled($0) }
            ))

            TextField("Cloud Base URL", text: Binding(
                get: { ai.settings.cloudBaseURL },
                set: { ai.settings.cloudBaseURL = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            TextField("Cloud Model", text: Binding(
                get: { ai.settings.cloudModelName },
                set: { ai.settings.cloudModelName = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                SecureField("API Key", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)

                Button("Set API Key") {
                    ai.storeCloudAPIKey(apiKeyDraft)
                    apiKeyDraft = ""
                }
                .buttonStyle(.bordered)

                Button("Clear") {
                    ai.clearCloudAPIKey()
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Button("Test Cloud") {
                    ai.testCloudConnection()
                }
                .buttonStyle(.bordered)
                .disabled(ai.settings.cloudEnabled == false)

                Text(ai.hasCloudAPIKey ? "API key stored" : "No API key")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                if let message = ai.cloudTestMessage, message.isEmpty == false {
                    Text("• \(message)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    // =====================================================
    // MARK: - Notes (RAG)
    // =====================================================

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Notes (RAG)")

            Toggle("Use Notes for Answers", isOn: Binding(
                get: { ai.memory.useNotesForAnswers },
                set: { ai.setUseNotesForAnswers($0) }
            ))

            HStack {
                Text("Stored notes: \(ai.noteCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear Notes") {
                    ai.clearAllNotes()
                }
                .buttonStyle(.bordered)
            }

            TextEditor(text: $notesDraft)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 90)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )

            HStack(spacing: 8) {
                Button("Add Notes") {
                    ai.addNotesFromText(notesDraft)
                    notesDraft = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.accentColor)
                .disabled(notesDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Import .txt") {
                    importNoteFile()
                }
                .buttonStyle(.bordered)

                Button("Clear Text") {
                    notesDraft = ""
                }
                .buttonStyle(.bordered)
            }

            if let message = ai.notesMessage, message.isEmpty == false {
                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // =====================================================
    // MARK: - Debug
    // =====================================================

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Debug")

            Text("Last provider: \(ai.providerStatus)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Text("Using cloud: \(ai.isUsingCloud ? "Yes" : "No")")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Text("Last request: \(ai.lastRequestDurationMs) ms")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if let providerError = ai.lastProviderError, providerError.isEmpty == false {
                Text("Last provider error: \(providerError)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            Text("Privacy: Local mode keeps prompts on this device. Cloud mode sends prompts to your configured endpoint.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // =====================================================
    // MARK: - Helpers
    // =====================================================

    private func syncDrafts() {
        topicsDraft = ai.topicsCSV
        weakTopicsDraft = ai.weakTopicsCSV
        coachNotesDraft = ai.memory.personalCoachNotes
    }

    private func importNoteFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText]

        if panel.runModal() == .OK, let url = panel.url {
            ai.importNotesFromFile(url)
        }
    }

    private func defaultBaseURL(for provider: AILocalProvider) -> String {
        switch provider {
        case .ollama:
            return "http://127.0.0.1:11434"
        case .lmStudio:
            return "http://127.0.0.1:1234"
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
    }
}
