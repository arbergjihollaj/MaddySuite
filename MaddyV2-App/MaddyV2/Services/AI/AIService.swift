//
//  AIService.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import Foundation
import Combine

// =====================================================
// MARK: - AIService
// [TAG: V2_AI_SERVICE]
// =====================================================

@MainActor
final class AIService: ObservableObject {
    @Published var mode: AIConversationMode = .study

    @Published var settings: AISettingsModel {
        didSet {
            storage.saveSettings(settings)
            Task { @MainActor [weak self] in
                self?.updateDailyChallengePrompt()
            }
        }
    }

    @Published var memory: AIMemorySnapshot {
        didSet {
            let normalized = memory.normalized()
            if memory != normalized {
                memory = normalized
                return
            }

            memoryStore.save(memory)

            if settings.language != memory.preferredLanguage {
                var updated = settings
                updated.language = memory.preferredLanguage
                settings = updated
            }

            Task { @MainActor [weak self] in
                self?.updateDailyChallengePrompt()
            }
        }
    }

    @Published private(set) var studyMessages: [AIMessage]
    @Published private(set) var chatMessages: [AIMessage]

    @Published private(set) var status: AIConnectionStatus = .offline
    @Published private(set) var providerStatus: String = "Offline"
    @Published private(set) var isUsingCloud: Bool = false
    @Published private(set) var lastProviderError: String?

    @Published private(set) var isRequestInFlight = false
    @Published private(set) var localModels: [String] = []
    @Published private(set) var cloudModels: [String] = []

    @Published var lastErrorMessage: String?
    @Published var localTestMessage: String?
    @Published var cloudTestMessage: String?
    @Published var notesMessage: String?

    @Published private(set) var isQuizSessionActive = false
    @Published private(set) var awaitingQuizAnswer = false
    @Published private(set) var awaitingQuizEvaluation = false

    @Published private(set) var dailyChallengePrompt: String = ""

    @Published private(set) var xpToastText: String?
    @Published private(set) var xpToastToken: Int = 0

    @Published private(set) var providerFallbackNotice: String?
    @Published private(set) var lastRequestDurationMs: Int = 0

    @Published private(set) var noteCount: Int = 0

    var onXPReward: ((Int, String) -> Void)?
    var gamificationContextProvider: (() -> String)?

    private let storage: AIStorage
    private let memoryStore: AIMemoryStore
    private let retrieval: AIRetrieval
    private let localClient: LocalLLMClient
    private let cloudClient: CloudLLMClient

    private var requestTask: Task<Void, Never>?
    private var dayTicker: AnyCancellable?
    private let streamingRenderer = AIStreamingRenderer()

    private var fallbackNoticeToken: Int = 0

    convenience init() {
        self.init(
            storage: AIStorage(),
            memoryStore: AIMemoryStore(),
            retrieval: AIRetrieval(),
            localClient: LocalLLMClient(),
            cloudClient: CloudLLMClient()
        )
    }

    init(
        storage: AIStorage,
        memoryStore: AIMemoryStore,
        retrieval: AIRetrieval,
        localClient: LocalLLMClient,
        cloudClient: CloudLLMClient
    ) {
        let loadedSettings = storage.loadSettings()

        let loadedMemory: AIMemorySnapshot
        if memoryStore.hasPersistedSnapshot {
            loadedMemory = memoryStore.load(fallbackLanguage: loadedSettings.language)
        } else {
            loadedMemory = AIMemorySnapshot.default(fallbackLanguage: loadedSettings.language)
            memoryStore.save(loadedMemory)
        }

        var syncedSettings = loadedSettings
        if syncedSettings.language != loadedMemory.preferredLanguage {
            syncedSettings.language = loadedMemory.preferredLanguage
            storage.saveSettings(syncedSettings)
        }

        let store = storage.loadChatStore()

        self.storage = storage
        self.memoryStore = memoryStore
        self.retrieval = retrieval
        self.localClient = localClient
        self.cloudClient = cloudClient
        self.settings = syncedSettings
        self.memory = loadedMemory
        self.studyMessages = store.studyMessages
        self.chatMessages = store.chatMessages

        refreshNotesState()
        ensureChallengeDay()
        updateDailyChallengePrompt()

        dayTicker = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.ensureChallengeDay()
                self.updateDailyChallengePrompt()
            }
    }

    deinit {
        requestTask?.cancel()
        dayTicker?.cancel()
    }

    // =====================================================
    // MARK: - Public Accessors
    // =====================================================

    var orderedTools: [AICoachTool] {
        memory.toolOrder
    }

    var activeModelName: String {
        if settings.useCloudForCurrentSession {
            return settings.cloudModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "cloud-model"
                : settings.cloudModelName
        }

        return settings.localModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "phi4-mini"
            : settings.localModelName
    }

    var activeModelOptions: [String] {
        let options = settings.useCloudForCurrentSession
            ? dedup(models: [settings.cloudModelName] + cloudModels)
            : dedup(models: [settings.localModelName] + localModels)

        return options.isEmpty ? [activeModelName] : options
    }

    var dailyChallengeProgressText: String {
        settings.dailyChallengeState.progressText
    }

    var dailyChallengeCompleted: Bool {
        settings.dailyChallengeState.completed
    }

    var hasCloudAPIKey: Bool {
        storage.loadCloudAPIKey()?.isEmpty == false
    }

    var hasNotes: Bool {
        noteCount > 0
    }

    var topicsCSV: String {
        memoryStore.tagsCSV(from: memory.topics)
    }

    var weakTopicsCSV: String {
        memoryStore.tagsCSV(from: memory.weakTopics)
    }

    func messages(for mode: AIConversationMode) -> [AIMessage] {
        switch mode {
        case .study:
            return studyMessages
        case .chat:
            return chatMessages
        }
    }

    // =====================================================
    // MARK: - Memory Mutations
    // =====================================================

    func setPreferredLanguage(_ language: AILanguage) {
        var updated = memory
        updated.preferredLanguage = language
        memory = updated
    }

    func setVerbosity(_ verbosity: AIMemoryVerbosity) {
        var updated = memory
        updated.verbosity = verbosity
        memory = updated
    }

    func setStrictness(_ strictness: AICoachingStrictness) {
        var updated = memory
        updated.coachingStrictness = strictness
        memory = updated
    }

    func setDefaultTool(_ tool: AICoachTool) {
        var updated = memory
        updated.defaultStudyTool = tool
        memory = updated
    }

    func setUseNotesForAnswers(_ enabled: Bool) {
        var updated = memory
        updated.useNotesForAnswers = enabled
        memory = updated
    }

    func updateTopicsCSV(_ raw: String) {
        var updated = memory
        updated.topics = memoryStore.parseTagsCSV(raw)
        memory = updated
    }

    func updateWeakTopicsCSV(_ raw: String) {
        var updated = memory
        updated.weakTopics = memoryStore.parseTagsCSV(raw)
        memory = updated
    }

    func updatePersonalCoachNotes(_ text: String) {
        var updated = memory
        updated.personalCoachNotes = text
        memory = updated
    }

    func moveToolOrder(from source: IndexSet, to destination: Int) {
        var updated = memory
        updated.toolOrder = movedArray(updated.toolOrder, from: source, to: destination)
        updated.toolOrder = AIMemorySnapshot.normalizeToolOrder(updated.toolOrder)
        memory = updated
    }

    // =====================================================
    // MARK: - Notes / Retrieval
    // =====================================================

    func addNotesFromText(_ text: String) {
        retrieval.addNote(text: text)
        refreshNotesState()
        notesMessage = memory.preferredLanguage == .german
            ? "Notiz hinzugefuegt."
            : "Notes added."
    }

    func importNotesFromFile(_ url: URL) {
        do {
            try retrieval.importNoteFile(url: url)
            refreshNotesState()
            notesMessage = memory.preferredLanguage == .german
                ? "Datei importiert."
                : "File imported."
        } catch {
            notesMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func clearAllNotes() {
        retrieval.clearNotes()
        refreshNotesState()
        notesMessage = memory.preferredLanguage == .german
            ? "Notizen geloescht."
            : "Notes cleared."
    }

    // =====================================================
    // MARK: - Settings Mutations
    // =====================================================

    func updateActiveModelName(_ value: String) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.useCloudForCurrentSession {
            settings.cloudModelName = cleaned
        } else {
            settings.localModelName = cleaned
        }
    }

    func storeCloudAPIKey(_ key: String) {
        let ok = storage.storeCloudAPIKey(key)
        cloudTestMessage = ok ? "API key saved in Keychain." : "Could not store API key in Keychain."
    }

    func clearCloudAPIKey() {
        let ok = storage.clearCloudAPIKey()
        cloudTestMessage = ok ? "API key removed from Keychain." : "Could not remove API key from Keychain."
    }

    func setCloudEnabled(_ enabled: Bool) {
        var updated = settings
        updated.cloudEnabled = enabled
        if enabled == false {
            updated.useCloudForCurrentSession = false
        }
        settings = updated
    }

    // =====================================================
    // MARK: - Connectivity Tests
    // =====================================================

    func testLocalConnection() {
        localTestMessage = "Testing local endpoint..."

        Task {
            do {
                let result = try await localClient.testConnection(settings: settings)
                localModels = result.models
                localTestMessage = result.message
                applyProviderState(.local)
                lastErrorMessage = nil
                lastProviderError = nil
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                localTestMessage = "Local test failed: \(message)"
                lastProviderError = message
                if status == .local {
                    applyProviderState(.offline)
                }
            }
        }
    }

    func testCloudConnection() {
        cloudTestMessage = "Testing cloud endpoint..."

        guard settings.cloudEnabled else {
            cloudTestMessage = "Cloud is disabled."
            return
        }

        guard let apiKey = storage.loadCloudAPIKey(), apiKey.isEmpty == false else {
            cloudTestMessage = "No API key set. Add one in Settings > AI."
            return
        }

        Task {
            do {
                let result = try await cloudClient.testConnection(settings: settings, apiKey: apiKey)
                cloudModels = result.models
                cloudTestMessage = result.message
                applyProviderState(.cloud)
                lastErrorMessage = nil
                lastProviderError = nil
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                cloudTestMessage = "Cloud test failed: \(message)"
                lastProviderError = message
                if status == .cloud {
                    applyProviderState(.offline)
                }
            }
        }
    }

    // =====================================================
    // MARK: - Chat / Study
    // =====================================================

    func sendChatMessage(_ text: String) {
        ensureChallengeDay()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        sendPrompt(
            displayUserText: trimmed,
            modelUserPrompt: AIPromptTemplates.generalChat(userInput: trimmed),
            mode: .chat,
            retrievalQuery: trimmed,
            rewardXP: nil,
            didGenerateFlashcards: false
        )
    }

    func sendStudyMessage(_ text: String) {
        ensureChallengeDay()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        sendPrompt(
            displayUserText: trimmed,
            modelUserPrompt: AIPromptTemplates.generalChat(userInput: trimmed),
            mode: .study,
            retrievalQuery: trimmed,
            rewardXP: nil,
            didGenerateFlashcards: false
        )
    }

    func runCoachTool(_ tool: AICoachTool, topic: String = "", notes: String = "", context: String = "") {
        ensureChallengeDay()

        let display = toolDisplayText(tool: tool, topic: topic, context: context)
        let prompt = toolPrompt(tool: tool, topic: topic, notes: notes, context: context)
        let query = [topic, notes, context].joined(separator: " ")

        if tool == .quiz {
            mode = .study
            isQuizSessionActive = true
            awaitingQuizAnswer = true
            awaitingQuizEvaluation = false
        }

        sendPrompt(
            displayUserText: display,
            modelUserPrompt: prompt,
            mode: tool == .quiz ? .study : mode,
            retrievalQuery: query,
            rewardXP: rewardForTool(tool),
            didGenerateFlashcards: tool == .flashcards
        )
    }

    func runStudyAction(_ action: StudyCoachAction, topic: String, notes: String) {
        ensureChallengeDay()

        switch action {
        case .explainSimply:
            runCoachTool(.explain, topic: topic, notes: notes)
        case .examSummary:
            runCoachTool(.summary, topic: topic, notes: notes)
        case .quizMe:
            runCoachTool(.quiz, topic: topic, notes: notes)
        case .flashcards:
            runCoachTool(.flashcards, topic: topic, notes: notes)
        case .practiceProblems:
            let merged = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Create 3 practice problems and concise solutions."
                : "\(notes)\n\nCreate 3 practice problems and concise solutions."
            runCoachTool(.plan, topic: topic, notes: merged)
        }
    }

    func runQuickAction(_ action: AIQuickAction, userContext: String) {
        ensureChallengeDay()

        switch action {
        case .explainConcept:
            runCoachTool(.explain, topic: userContext)
        case .makeFlashcards:
            runCoachTool(.flashcards, topic: userContext)
        case .generateQuiz:
            runCoachTool(.quiz, topic: userContext)
        case .summarizeNotes:
            runCoachTool(.summary, topic: userContext)
        case .planStudySession:
            runCoachTool(.plan, topic: userContext)
        }
    }

    func submitQuizAnswer(_ answer: String) {
        ensureChallengeDay()

        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        guard isQuizSessionActive, awaitingQuizAnswer else { return }

        awaitingQuizAnswer = false
        awaitingQuizEvaluation = true

        sendPrompt(
            displayUserText: trimmed,
            modelUserPrompt: AIPromptTemplates.quizEvaluateAnswer(
                answer: trimmed,
                language: memory.preferredLanguage
            ),
            mode: .study,
            retrievalQuery: trimmed,
            rewardXP: nil,
            didGenerateFlashcards: false
        )
    }

    func markQuizAnswer(correct: Bool) {
        ensureChallengeDay()
        guard awaitingQuizEvaluation else { return }

        awaitingQuizEvaluation = false

        if correct {
            rewardXP(15, reason: "Quiz correct")
            settings.dailyChallengeState.quizCorrectCount += 1
            applyDailyChallengeIfNeeded()
        }

        requestNextQuizQuestion()
    }

    func requestNextQuizQuestion() {
        guard isQuizSessionActive else { return }

        awaitingQuizAnswer = true
        awaitingQuizEvaluation = false

        sendPrompt(
            displayUserText: memory.preferredLanguage == .german ? "Naechste Frage" : "Next question",
            modelUserPrompt: AIPromptTemplates.quizOneByOne(
                topic: memory.topics.first ?? "",
                notes: "",
                language: memory.preferredLanguage
            ),
            mode: .study,
            retrievalQuery: memory.topics.joined(separator: " "),
            rewardXP: nil,
            didGenerateFlashcards: false
        )
    }

    func endQuizSession() {
        isQuizSessionActive = false
        awaitingQuizAnswer = false
        awaitingQuizEvaluation = false
    }

    func clearChat(for mode: AIConversationMode) {
        switch mode {
        case .study:
            studyMessages = []
        case .chat:
            chatMessages = []
        }
        persistChats()
    }

    func cancelCurrentRequest() {
        requestTask?.cancel()
        requestTask = nil
        isRequestInFlight = false
    }

    func generatePersonalizedDailyChallenges(
        dayKey: String,
        fallback: [GamificationDailyChallenge],
        context: String
    ) async -> [GamificationDailyChallenge]? {
        guard fallback.isEmpty == false else { return nil }

        let relevantNotes = memory.useNotesForAnswers
            ? retrieval.topChunks(
                for: "daily challenge study productivity \(memory.topics.joined(separator: " ")) \(memory.weakTopics.joined(separator: " "))",
                limit: 2
            )
            : []

        let systemPrompt = AIPromptTemplates.dailyChallengeSystemPrompt(language: memory.preferredLanguage)
        let userPrompt = AIPromptTemplates.dailyChallengeUserPrompt(
            language: memory.preferredLanguage,
            dayKey: dayKey,
            fallback: fallback,
            memory: memory,
            context: context,
            relevantNotes: relevantNotes
        )

        let conversation = [
            AIMessage(role: .system, content: systemPrompt),
            AIMessage(role: .user, content: userPrompt)
        ]

        do {
            let routed = try await sendWithRouting(conversation: conversation)
            applyProviderState(routed.backend)
            if routed.usedCloudFallback {
                showFallbackNotice(
                    memory.preferredLanguage == .german
                        ? "Lokales Modell nicht erreichbar, Cloud-Fallback fuer Daily Challenges."
                        : "Local model unavailable, cloud fallback used for daily challenges."
                )
            }
            return parsePersonalizedChallenges(
                routed.response.text,
                dayKey: dayKey,
                fallback: fallback
            )
        } catch {
            lastProviderError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    // =====================================================
    // MARK: - Internal Send Flow
    // =====================================================

    private func sendPrompt(
        displayUserText: String,
        modelUserPrompt: String,
        mode: AIConversationMode,
        retrievalQuery: String,
        rewardXP: (Int, String)?,
        didGenerateFlashcards: Bool
    ) {
        requestTask?.cancel()
        requestTask = nil

        lastErrorMessage = nil
        isRequestInFlight = true

        appendMessage(role: .user, content: displayUserText, mode: mode)

        let notes = memory.useNotesForAnswers
            ? retrieval.topChunks(for: retrievalQuery, limit: 3)
            : []

        let systemPrompt = AIPromptTemplates.baseSystemPrompt(
            language: memory.preferredLanguage,
            verbosity: memory.verbosity,
            strictness: memory.coachingStrictness,
            userProfile: memory.userProfile,
            gamificationContext: gamificationContextProvider?(),
            relevantNotes: notes
        )

        let conversation = buildConversation(
            mode: mode,
            systemPrompt: systemPrompt,
            modelUserPrompt: modelUserPrompt
        )

        let startedAt = Date()

        requestTask = Task { [weak self] in
            guard let self else { return }

            do {
                let routed = try await self.sendWithRouting(conversation: conversation)
                try Task.checkCancellation()

                self.lastRequestDurationMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
                self.applyProviderState(routed.backend)
                self.lastErrorMessage = nil
                self.lastProviderError = nil

                if routed.usedCloudFallback {
                    self.showFallbackNotice(
                        self.memory.preferredLanguage == .german
                            ? "Lokales Modell nicht erreichbar, Cloud-Fallback aktiv."
                            : "Local model unavailable, using cloud fallback."
                    )
                }

                try await self.appendAssistantResponse(routed.response.text, mode: mode)

                if let rewardXP {
                    self.rewardXP(rewardXP.0, reason: rewardXP.1)
                }

                if didGenerateFlashcards {
                    self.settings.dailyChallengeState.flashcardsGenerated = true
                    self.applyDailyChallengeIfNeeded()
                }
            } catch {
                if error is CancellationError {
                    self.lastErrorMessage = nil
                } else {
                    self.applyProviderState(.offline)
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.lastErrorMessage = message
                    self.lastProviderError = message
                }
            }

            self.isRequestInFlight = false
            self.requestTask = nil
        }
    }

    private func buildConversation(mode: AIConversationMode, systemPrompt: String, modelUserPrompt: String) -> [AIMessage] {
        var base = Array(messages(for: mode).suffix(40))

        if let lastUser = base.lastIndex(where: { $0.role == .user }) {
            base[lastUser].content = modelUserPrompt
        }

        return [AIMessage(role: .system, content: systemPrompt)] + base
    }

    private struct RoutedResult {
        let response: AIChatResponse
        let backend: AIConnectionStatus
        let usedCloudFallback: Bool
    }

    private func sendWithRouting(conversation: [AIMessage]) async throws -> RoutedResult {
        var localError: String?
        var cloudError: String?

        let order = routeOrder()

        for route in order {
            try Task.checkCancellation()

            switch route {
            case .local:
                do {
                    let request = AIChatRequest(
                        messages: conversation,
                        model: settings.localModelName.isEmpty ? "phi4-mini" : settings.localModelName,
                        temperature: 0.35,
                        maxTokens: settings.maxTokens,
                        stream: settings.streamingEnabled
                    )
                    let response = try await localClient.send(request: request, settings: settings)
                    return RoutedResult(response: response, backend: .local, usedCloudFallback: false)
                } catch {
                    localError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }

            case .cloud:
                do {
                    guard settings.cloudEnabled else {
                        throw AIError.cloudNotConfigured
                    }
                    guard let apiKey = storage.loadCloudAPIKey(), apiKey.isEmpty == false else {
                        throw AIError.missingCloudAPIKey
                    }

                    let request = AIChatRequest(
                        messages: conversation,
                        model: settings.cloudModelName.isEmpty ? "cloud-model" : settings.cloudModelName,
                        temperature: 0.3,
                        maxTokens: settings.maxTokens,
                        stream: settings.streamingEnabled
                    )
                    let response = try await cloudClient.send(request: request, settings: settings, apiKey: apiKey)
                    let usedFallback = order.first == .local && localError != nil
                    return RoutedResult(response: response, backend: .cloud, usedCloudFallback: usedFallback)
                } catch {
                    cloudError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }

            case .offline:
                break
            }
        }

        throw AIError.allBackendsUnavailable(local: localError, cloud: cloudError)
    }

    private func routeOrder() -> [AIBackendRoute] {
        if settings.useCloudForCurrentSession {
            return [.cloud, .local]
        }
        return [.local, .cloud]
    }

    private func appendMessage(role: AIMessageRole, content: String, mode: AIConversationMode) {
        let message = AIMessage(role: role, content: content)
        switch mode {
        case .study:
            studyMessages = clipped(studyMessages + [message])
        case .chat:
            chatMessages = clipped(chatMessages + [message])
        }
        persistChats()
    }

    private func appendAssistantResponse(_ text: String, mode: AIConversationMode) async throws {
        appendMessage(role: .assistant, content: "", mode: mode)

        if settings.streamingEnabled {
            let checkpoints = await streamingRenderer.streamingCheckpoints(
                text: text,
                wordsPerChunk: 20
            )

            for partial in checkpoints {
                try Task.checkCancellation()
                updateLastAssistantMessage(mode: mode, content: partial)
                try await Task.sleep(nanoseconds: 40_000_000)
            }
        }

        updateLastAssistantMessage(mode: mode, content: text)
        persistChats()
    }

    private func updateLastAssistantMessage(mode: AIConversationMode, content: String) {
        switch mode {
        case .study:
            guard studyMessages.isEmpty == false else { return }
            var updated = studyMessages
            updated[updated.count - 1].content = content
            studyMessages = clipped(updated)
        case .chat:
            guard chatMessages.isEmpty == false else { return }
            var updated = chatMessages
            updated[updated.count - 1].content = content
            chatMessages = clipped(updated)
        }
    }

    private func clipped(_ messages: [AIMessage]) -> [AIMessage] {
        Array(messages.suffix(AIStorage.maxMessagesPerMode))
    }

    private func persistChats() {
        storage.saveChatStore(AIChatStore(studyMessages: studyMessages, chatMessages: chatMessages))
    }

    // =====================================================
    // MARK: - Challenge + XP
    // =====================================================

    private func ensureChallengeDay() {
        let key = dayKey(for: Date())
        if settings.dailyChallengeState.dayKey != key {
            settings.dailyChallengeState = AIDailyStudyChallengeState(
                dayKey: key,
                quizCorrectCount: 0,
                flashcardsGenerated: false,
                rewardGranted: false
            )
        }
    }

    private func updateDailyChallengePrompt() {
        let key = settings.dailyChallengeState.dayKey.isEmpty
            ? dayKey(for: Date())
            : settings.dailyChallengeState.dayKey

        dailyChallengePrompt = AIPromptTemplates.dailyStudyChallenge(
            dayKey: key,
            language: memory.preferredLanguage
        )
    }

    private func applyDailyChallengeIfNeeded() {
        guard settings.dailyChallengeState.completed,
              settings.dailyChallengeState.rewardGranted == false else {
            return
        }

        settings.dailyChallengeState.rewardGranted = true
        rewardXP(25, reason: "Daily Study Challenge")
    }

    private func rewardXP(_ amount: Int, reason: String) {
        guard amount > 0 else { return }

        onXPReward?(amount, reason)

        xpToastText = "+\(amount) XP · \(reason)"
        xpToastToken += 1

        Task {
            try? await Task.sleep(nanoseconds: 1_650_000_000)
            if self.xpToastToken > 0 {
                self.xpToastText = nil
            }
        }
    }

    private func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // =====================================================
    // MARK: - Provider / UI Helpers
    // =====================================================

    private func applyProviderState(_ state: AIConnectionStatus) {
        status = state

        switch state {
        case .local:
            isUsingCloud = false
            providerStatus = settings.localProvider == .ollama ? "Local (Ollama)" : "Local (LM Studio)"
        case .cloud:
            isUsingCloud = true
            providerStatus = "Cloud"
        case .offline:
            isUsingCloud = false
            providerStatus = "Offline"
        }
    }

    private func showFallbackNotice(_ text: String) {
        fallbackNoticeToken += 1
        let token = fallbackNoticeToken
        providerFallbackNotice = text

        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if token == self.fallbackNoticeToken {
                self.providerFallbackNotice = nil
            }
        }
    }

    private func toolDisplayText(tool: AICoachTool, topic: String, context: String) -> String {
        let source = [topic, context]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.isEmpty == false })

        if let source {
            return "\(tool.title): \(source)"
        }
        return tool.title
    }

    private func rewardForTool(_ tool: AICoachTool) -> (Int, String)? {
        switch tool {
        case .explain:
            return (5, "Explain simply")
        case .summary:
            return (10, "Exam-ready summary")
        default:
            return nil
        }
    }

    private func toolPrompt(tool: AICoachTool, topic: String, notes: String, context: String) -> String {
        switch tool {
        case .explain:
            return AIPromptTemplates.explainSimple(topic: topic, notes: notes, language: memory.preferredLanguage)
        case .summary:
            return AIPromptTemplates.examReadySummary(topic: topic, notes: notes, language: memory.preferredLanguage)
        case .quiz:
            return AIPromptTemplates.quizOneByOne(topic: topic, notes: notes, language: memory.preferredLanguage)
        case .flashcards:
            return AIPromptTemplates.flashcards(topic: topic, notes: notes, language: memory.preferredLanguage)
        case .plan:
            return AIPromptTemplates.studyPlan(topic: topic, minutes: 50, language: memory.preferredLanguage)
        case .motivation:
            let resolved = context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? topic : context
            return AIPromptTemplates.motivationCoach(context: resolved, language: memory.preferredLanguage)
        }
    }

    private struct AIDailyChallengeDraft: Decodable {
        let kind: String
        let title: String
        let description: String
        let target: Int?
        let rewardXP: Int?
    }

    private func parsePersonalizedChallenges(
        _ raw: String,
        dayKey: String,
        fallback: [GamificationDailyChallenge]
    ) -> [GamificationDailyChallenge]? {
        guard let json = extractJSONArray(from: raw),
              let data = json.data(using: .utf8),
              let drafts = try? JSONDecoder().decode([AIDailyChallengeDraft].self, from: data) else {
            return nil
        }

        var draftsByKind: [GamificationChallengeKind: AIDailyChallengeDraft] = [:]
        for draft in drafts {
            guard let kind = GamificationChallengeKind(rawValue: draft.kind),
                  draftsByKind[kind] == nil else {
                continue
            }
            draftsByKind[kind] = draft
        }

        guard draftsByKind.isEmpty == false else { return nil }

        return fallback.map { base in
            let draft = draftsByKind[base.kind]
            let title = draft?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = draft?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let reward = max(10, min(50, draft?.rewardXP ?? base.rewardXP))
            let target = normalizedChallengeTarget(
                kind: base.kind,
                proposed: draft?.target ?? base.target,
                fallback: base.target
            )

            return GamificationDailyChallenge(
                id: "\(dayKey)-\(base.kind.rawValue)",
                kind: base.kind,
                title: title.isEmpty ? base.title : title,
                description: description.isEmpty ? base.description : description,
                rewardXP: reward,
                progress: base.progress,
                target: target,
                completed: base.completed,
                rewarded: base.rewarded
            )
        }
    }

    private func normalizedChallengeTarget(kind: GamificationChallengeKind, proposed: Int, fallback: Int) -> Int {
        switch kind {
        case .earlyWin, .consistency:
            return 1
        case .taskSprint:
            return max(1, min(8, proposed > 0 ? proposed : fallback))
        case .habitCombo:
            return max(1, min(5, proposed > 0 ? proposed : fallback))
        case .cleanInbox:
            return max(1, min(10, proposed > 0 ? proposed : fallback))
        case .deepFocus:
            return max(15, min(120, proposed > 0 ? proposed : fallback))
        case .studySession:
            return max(15, min(180, proposed > 0 ? proposed : fallback))
        default:
            return max(1, proposed > 0 ? proposed : fallback)
        }
    }

    private func extractJSONArray(from text: String) -> String? {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start <= end else {
            return nil
        }
        return String(text[start...end])
    }

    private func refreshNotesState() {
        noteCount = retrieval.noteCount
    }

    private func dedup(models: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for model in models {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }

        return result
    }

    private func movedArray<T>(_ values: [T], from source: IndexSet, to destination: Int) -> [T] {
        var array = values
        let items = source.sorted().map { array[$0] }
        for index in source.sorted(by: >) {
            array.remove(at: index)
        }

        var insertIndex = destination
        for removed in source where removed < destination {
            insertIndex -= 1
        }

        array.insert(contentsOf: items, at: max(0, min(insertIndex, array.count)))
        return array
    }
}

actor AIStreamingRenderer {
    func streamingCheckpoints(text: String, wordsPerChunk: Int) -> [String] {
        let sanitizedChunk = max(1, wordsPerChunk)
        let words = text.split(separator: " ").map(String.init)

        guard words.isEmpty == false else {
            return [text]
        }

        var result: [String] = []
        result.reserveCapacity((words.count / sanitizedChunk) + 1)

        var staged = ""
        for index in words.indices {
            if staged.isEmpty {
                staged = words[index]
            } else {
                staged += " \(words[index])"
            }

            let checkpoint = index % sanitizedChunk == 0 || index == words.count - 1
            if checkpoint {
                result.append(staged)
            }
        }

        return result
    }
}
