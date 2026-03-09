//
//  AIStorage.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import Foundation
import Security

// =====================================================
// MARK: - AIStorage
// [TAG: V2_AI_STORAGE]
// =====================================================

final class AIStorage {
    static let maxMessagesPerMode = 200

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let directoryURL: URL
    private let chatsURL: URL
    private let settingsURL: URL

    private let keychainService = "com.arber.MaddyV2.ai"
    private let cloudAPIKeyAccount = "cloud_api_key"

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        directoryURL = Self.aiDirectory
        chatsURL = directoryURL.appendingPathComponent("chats.json")
        settingsURL = directoryURL.appendingPathComponent("ai_settings.json")

        ensureDirectory()
    }

    func loadSettings() -> AISettingsModel {
        guard let data = try? Data(contentsOf: settingsURL),
              let model = try? decoder.decode(AISettingsModel.self, from: data) else {
            return AISettingsModel.default()
        }
        return model
    }

    func saveSettings(_ settings: AISettingsModel) {
        ensureDirectory()
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    func loadChatStore() -> AIChatStore {
        guard let data = try? Data(contentsOf: chatsURL),
              let store = try? decoder.decode(AIChatStore.self, from: data) else {
            return .empty
        }

        return AIChatStore(
            studyMessages: Array(store.studyMessages.suffix(Self.maxMessagesPerMode)),
            chatMessages: Array(store.chatMessages.suffix(Self.maxMessagesPerMode))
        )
    }

    func saveChatStore(_ store: AIChatStore) {
        ensureDirectory()

        let clipped = AIChatStore(
            studyMessages: Array(store.studyMessages.suffix(Self.maxMessagesPerMode)),
            chatMessages: Array(store.chatMessages.suffix(Self.maxMessagesPerMode))
        )

        guard let data = try? encoder.encode(clipped) else { return }
        try? data.write(to: chatsURL, options: .atomic)
    }

    func storeCloudAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let valueData = Data(trimmed.utf8)

        if trimmed.isEmpty {
            return clearCloudAPIKey()
        }

        let baseQuery = keychainBaseQuery()

        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = valueData
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    func loadCloudAPIKey() -> String? {
        var query = keychainBaseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              value.isEmpty == false else {
            return nil
        }

        return value
    }

    func clearCloudAPIKey() -> Bool {
        let status = SecItemDelete(keychainBaseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func keychainBaseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: cloudAPIKeyAccount
        ]
    }

    private func ensureDirectory() {
        if FileManager.default.fileExists(atPath: directoryURL.path) == false {
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    static var aiDirectory: URL {
        JSONStorageService.baseDirectory.appendingPathComponent("ai", isDirectory: true)
    }
}
