//
//  AIModels.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import Foundation

// =====================================================
// MARK: - Core Models
// [TAG: V2_AI_MODELS]
// =====================================================

enum AIConversationMode: String, Codable, CaseIterable, Identifiable {
    case study
    case chat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .study: return "Study"
        case .chat: return "Chat"
        }
    }
}

enum AIMessageRole: String, Codable {
    case system
    case user
    case assistant
}

struct AIMessage: Identifiable, Codable, Equatable {
    var id: UUID
    var role: AIMessageRole
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), role: AIMessageRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct AIChatRequest {
    var messages: [AIMessage]
    var model: String
    var temperature: Double
    var maxTokens: Int
    var stream: Bool
}

struct AIChatResponse {
    var text: String
    var model: String
}

// =====================================================
// MARK: - Settings
// [TAG: V2_AI_SETTINGS]
// =====================================================

enum AILocalProvider: String, Codable, CaseIterable, Identifiable {
    case ollama = "Ollama"
    case lmStudio = "LMStudio"

    var id: String { rawValue }
}

enum AIBackendPreference: String, Codable, CaseIterable, Identifiable {
    case local
    case cloud

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

enum AIBackendRoute: String {
    case local
    case cloud
    case offline
}

enum AILanguage: String, Codable, CaseIterable, Identifiable {
    case german
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .german: return "German"
        case .english: return "English"
        }
    }

    var localeCode: String {
        switch self {
        case .german: return "de"
        case .english: return "en"
        }
    }
}

struct AIDailyStudyChallengeState: Codable {
    var dayKey: String
    var quizCorrectCount: Int
    var flashcardsGenerated: Bool
    var rewardGranted: Bool

    static let empty = AIDailyStudyChallengeState(
        dayKey: "",
        quizCorrectCount: 0,
        flashcardsGenerated: false,
        rewardGranted: false
    )

    var completed: Bool {
        quizCorrectCount >= 3 || flashcardsGenerated
    }

    var progressText: String {
        if flashcardsGenerated {
            return "Flashcards done"
        }
        return "Quiz correct: \(quizCorrectCount)/3"
    }
}

struct AISettingsModel: Codable {
    var localProvider: AILocalProvider
    var localBaseURL: String
    var localModelName: String

    var cloudEnabled: Bool
    var cloudBaseURL: String
    var cloudModelName: String

    var defaultBackend: AIBackendPreference
    var useCloudForCurrentSession: Bool

    var cloudTimeout: Double
    var maxTokens: Int
    var streamingEnabled: Bool

    var language: AILanguage
    var dailyChallengeState: AIDailyStudyChallengeState

    static func `default`() -> AISettingsModel {
        let locale = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        let language: AILanguage = locale.hasPrefix("de") ? .german : .english

        return AISettingsModel(
            localProvider: .ollama,
            localBaseURL: "http://127.0.0.1:11434",
            localModelName: "phi4-mini",
            cloudEnabled: false,
            cloudBaseURL: "",
            cloudModelName: "",
            defaultBackend: .local,
            useCloudForCurrentSession: false,
            cloudTimeout: 60,
            maxTokens: 1024,
            streamingEnabled: true,
            language: language,
            dailyChallengeState: .empty
        )
    }
}

struct AIChatStore: Codable {
    var studyMessages: [AIMessage]
    var chatMessages: [AIMessage]

    static let empty = AIChatStore(studyMessages: [], chatMessages: [])
}

struct AIConnectionTestResult {
    var success: Bool
    var message: String
    var models: [String]
}

// =====================================================
// MARK: - UI Models
// [TAG: V2_AI_UI_MODELS]
// =====================================================

enum AIConnectionStatus: String {
    case local = "Local"
    case cloud = "Cloud"
    case offline = "Offline"
}

enum StudyCoachAction: String, CaseIterable, Identifiable {
    case explainSimply
    case examSummary
    case quizMe
    case flashcards
    case practiceProblems

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explainSimply: return "Explain simply"
        case .examSummary: return "Exam-ready summary"
        case .quizMe: return "Quiz me"
        case .flashcards: return "Flashcards"
        case .practiceProblems: return "Practice problems"
        }
    }

    var rewardXP: Int {
        switch self {
        case .explainSimply: return 5
        case .examSummary: return 10
        case .quizMe: return 0
        case .flashcards: return 0
        case .practiceProblems: return 0
        }
    }
}

enum AIQuickAction: String, CaseIterable, Identifiable {
    case explainConcept
    case makeFlashcards
    case generateQuiz
    case summarizeNotes
    case planStudySession

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explainConcept: return "Explain concept"
        case .makeFlashcards: return "Make flashcards"
        case .generateQuiz: return "Generate quiz"
        case .summarizeNotes: return "Summarize notes"
        case .planStudySession: return "Plan study session"
        }
    }
}
