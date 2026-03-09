//
//  AIRetrieval.swift
//  MaddyV2
//
//  Created by Arber on 04.03.26.
//

import Foundation

// =====================================================
// MARK: - Retrieval Models
// [TAG: V2_AI_RETRIEVAL_MODELS]
// =====================================================

private struct AINoteDocument: Codable, Identifiable, Equatable {
    var id: UUID
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), content: String, createdAt: Date = Date()) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
    }
}

private struct AINoteChunk {
    var noteID: UUID
    var content: String
}

private struct AIScoredChunk {
    var chunk: AINoteChunk
    var score: Int
}

// =====================================================
// MARK: - Retrieval Store
// [TAG: V2_AI_RETRIEVAL]
// =====================================================

final class AIRetrieval {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let fileURL: URL

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let directory = AIStorage.aiDirectory
        fileURL = directory.appendingPathComponent("notes.json")

        if FileManager.default.fileExists(atPath: directory.path) == false {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    var noteCount: Int {
        loadNotes().count
    }

    func addNote(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        var notes = loadNotes()
        notes.append(AINoteDocument(content: trimmed))
        save(notes)
    }

    func importNoteFile(url: URL) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        addNote(text: content)
    }

    func clearNotes() {
        save([])
    }

    func topChunks(for query: String, limit: Int = 3) -> [String] {
        let chunks = loadNotes().flatMap { chunk(text: $0.content, noteID: $0.id) }
        guard chunks.isEmpty == false else { return [] }

        let queryTokens = tokens(in: query)

        if queryTokens.isEmpty {
            return chunks
                .prefix(limit)
                .map { $0.content }
        }

        let scored = chunks.map { chunk in
            AIScoredChunk(chunk: chunk, score: score(chunk: chunk.content, queryTokens: queryTokens))
        }

        return scored
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.chunk.content.count < rhs.chunk.content.count
                }
                return lhs.score > rhs.score
            }
            .prefix(limit)
            .map { $0.chunk.content }
    }

    // =====================================================
    // MARK: - Helpers
    // =====================================================

    private func loadNotes() -> [AINoteDocument] {
        guard let data = try? Data(contentsOf: fileURL),
              let notes = try? decoder.decode([AINoteDocument].self, from: data) else {
            return []
        }
        return notes
    }

    private func save(_ notes: [AINoteDocument]) {
        guard let data = try? encoder.encode(notes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func chunk(text: String, noteID: UUID) -> [AINoteChunk] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.isEmpty == false else { return [] }

        let chars = Array(normalized)
        let chunkSize = 900
        let overlap = 180

        var index = 0
        var result: [AINoteChunk] = []

        while index < chars.count {
            let end = min(chars.count, index + chunkSize)
            let slice = String(chars[index..<end]).trimmingCharacters(in: .whitespacesAndNewlines)

            if slice.isEmpty == false {
                result.append(AINoteChunk(noteID: noteID, content: slice))
            }

            if end >= chars.count { break }
            index = max(0, end - overlap)
        }

        return result
    }

    private func score(chunk: String, queryTokens: Set<String>) -> Int {
        guard queryTokens.isEmpty == false else { return 0 }

        let chunkTokens = tokens(in: chunk)
        let overlap = queryTokens.intersection(chunkTokens)
        guard overlap.isEmpty == false else { return 0 }

        var score = overlap.count * 10

        let normalizedChunk = chunk.lowercased()
        for token in overlap {
            if normalizedChunk.contains("\(token) ") || normalizedChunk.hasPrefix(token) {
                score += 2
            }
        }

        return score
    }

    private func tokens(in text: String) -> Set<String> {
        let cleaned = text.lowercased()
        let scalars = cleaned.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }

        let normalized = String(scalars)
        let parts = normalized
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 }

        return Set(parts)
    }
}
