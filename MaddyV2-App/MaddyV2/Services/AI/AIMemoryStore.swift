//
//  AIMemoryStore.swift
//  MaddyV2
//
//  Created by Arber on 04.03.26.
//

import Foundation

// =====================================================
// MARK: - Memory Models
// [TAG: V2_AI_MEMORY_MODELS]
// =====================================================

enum AIMemoryVerbosity: String, Codable, CaseIterable, Identifiable {
    case short
    case normal
    case detailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .short: return "Short"
        case .normal: return "Normal"
        case .detailed: return "Detailed"
        }
    }
}

enum AICoachingStrictness: String, Codable, CaseIterable, Identifiable {
    case gentle
    case normal
    case strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle: return "Gentle"
        case .normal: return "Normal"
        case .strict: return "Strict"
        }
    }
}

enum AICoachTool: String, Codable, CaseIterable, Identifiable {
    case explain
    case summary
    case quiz
    case flashcards
    case plan
    case motivation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explain: return "Explain"
        case .summary: return "Summary"
        case .quiz: return "Quiz"
        case .flashcards: return "Flashcards"
        case .plan: return "Plan"
        case .motivation: return "Motivation"
        }
    }

    var icon: String {
        switch self {
        case .explain: return "text.book.closed"
        case .summary: return "list.bullet.rectangle.portrait"
        case .quiz: return "questionmark.circle"
        case .flashcards: return "rectangle.stack"
        case .plan: return "calendar.badge.clock"
        case .motivation: return "bolt.heart"
        }
    }
}

struct AIUserProfileSnapshot: Codable, Equatable {
    var topics: [String]
    var weakTopics: [String]
    var coachNotes: String
}

struct AIMemorySnapshot: Codable, Equatable {
    var preferredLanguage: AILanguage
    var verbosity: AIMemoryVerbosity
    var coachingStrictness: AICoachingStrictness
    var defaultStudyTool: AICoachTool

    var topics: [String]
    var weakTopics: [String]
    var personalCoachNotes: String

    var toolOrder: [AICoachTool]
    var useNotesForAnswers: Bool

    static func `default`(fallbackLanguage: AILanguage? = nil) -> AIMemorySnapshot {
        let locale = Locale.current.language.languageCode?.identifier.lowercased() ?? "en"
        let detectedLanguage: AILanguage = locale.hasPrefix("de") ? .german : .english

        return AIMemorySnapshot(
            preferredLanguage: fallbackLanguage ?? detectedLanguage,
            verbosity: .normal,
            coachingStrictness: .normal,
            defaultStudyTool: .explain,
            topics: [],
            weakTopics: [],
            personalCoachNotes: "",
            toolOrder: AICoachTool.allCases,
            useNotesForAnswers: true
        )
    }

    var userProfile: AIUserProfileSnapshot {
        AIUserProfileSnapshot(
            topics: topics,
            weakTopics: weakTopics,
            coachNotes: personalCoachNotes
        )
    }

    func normalized() -> AIMemorySnapshot {
        var copy = self
        copy.topics = sanitizeTags(topics)
        copy.weakTopics = sanitizeTags(weakTopics)
        copy.personalCoachNotes = personalCoachNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.toolOrder = Self.normalizeToolOrder(copy.toolOrder)

        if copy.toolOrder.contains(copy.defaultStudyTool) == false {
            copy.defaultStudyTool = copy.toolOrder.first ?? .explain
        }

        return copy
    }

    static func normalizeToolOrder(_ order: [AICoachTool]) -> [AICoachTool] {
        var seen = Set<AICoachTool>()
        var normalized: [AICoachTool] = []

        for tool in order where seen.insert(tool).inserted {
            normalized.append(tool)
        }

        for tool in AICoachTool.allCases where seen.contains(tool) == false {
            normalized.append(tool)
        }

        return normalized
    }

    private func sanitizeTags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for item in values {
            let clean = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard clean.isEmpty == false else { continue }
            let key = clean.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(clean)
        }

        return result
    }
}

// =====================================================
// MARK: - Memory Store
// [TAG: V2_AI_MEMORY_STORE]
// =====================================================

final class AIMemoryStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()

        let directory = AIStorage.aiDirectory
        fileURL = directory.appendingPathComponent("memory.json")
        ensureDirectoryExists(at: directory)
    }

    var hasPersistedSnapshot: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    func load(fallbackLanguage: AILanguage? = nil) -> AIMemorySnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(AIMemorySnapshot.self, from: data) else {
            return AIMemorySnapshot.default(fallbackLanguage: fallbackLanguage)
        }

        return snapshot.normalized()
    }

    func save(_ snapshot: AIMemorySnapshot) {
        let normalized = snapshot.normalized()
        guard let data = try? encoder.encode(normalized) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func parseTagsCSV(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    func tagsCSV(from tags: [String]) -> String {
        tags.joined(separator: ", ")
    }

    private func ensureDirectoryExists(at url: URL) {
        if FileManager.default.fileExists(atPath: url.path) == false {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
