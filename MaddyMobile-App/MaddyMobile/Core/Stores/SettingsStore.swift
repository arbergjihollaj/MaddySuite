import Foundation
import SwiftUI

// =====================================================
// MARK: - SettingsStore
// [TAG: MOBILE_SETTINGS_STORE]
// =====================================================

@MainActor
final class SettingsStore: ObservableObject {
    struct State: Codable {
        var accentHex: String
        var soundEnabled: Bool
        var exportPlaceholderEnabled: Bool
        var iCloudSyncEnabled: Bool
        var syncFolderBookmark: Data?
        var syncFolderDisplayName: String?
        var lastSuccessfulSyncAt: Date?
        var lastModifiedAt: Date?
    }

    struct CloudSnapshot: Codable {
        var accentHex: String
        var soundEnabled: Bool
        var exportPlaceholderEnabled: Bool
        var modifiedAt: Date
    }

    private struct LegacyState: Codable {
        var accentHex: String
        var soundEnabled: Bool
        var exportPlaceholderEnabled: Bool
    }

    @Published var accentHex: String {
        didSet { handleSyncedPreferenceMutation() }
    }

    @Published var soundEnabled: Bool {
        didSet { handleSyncedPreferenceMutation() }
    }

    @Published var exportPlaceholderEnabled: Bool {
        didSet { handleSyncedPreferenceMutation() }
    }

    @Published var iCloudSyncEnabled: Bool {
        didSet {
            guard isApplyingCloudSnapshot == false else { return }
            persist()
            onICloudSyncPreferenceChanged?(iCloudSyncEnabled)
        }
    }

    @Published private(set) var lastSuccessfulSyncAt: Date?
    @Published private(set) var syncFolderDisplayName: String?

    let syncStatusPlaceholder = "Sync with Mac (Coming Later)"

    var onDataChanged: (() -> Void)?
    var onICloudSyncPreferenceChanged: ((Bool) -> Void)?

    private let storage: LocalJSONStorage
    private let fileName = "settings.json"
    private(set) var lastModifiedAt: Date
    private var syncFolderBookmark: Data?
    private var isApplyingCloudSnapshot = false

    init(storage: LocalJSONStorage = .shared) {
        self.storage = storage

        let defaultModifiedAt = Date.distantPast
        if let loaded = storage.loadIfPresent(State.self, from: fileName) {
            accentHex = loaded.accentHex
            soundEnabled = loaded.soundEnabled
            exportPlaceholderEnabled = loaded.exportPlaceholderEnabled
            iCloudSyncEnabled = loaded.iCloudSyncEnabled
            syncFolderBookmark = loaded.syncFolderBookmark
            syncFolderDisplayName = loaded.syncFolderDisplayName
            lastSuccessfulSyncAt = loaded.lastSuccessfulSyncAt
            lastModifiedAt = loaded.lastModifiedAt ?? defaultModifiedAt
        } else if let legacy = storage.loadIfPresent(LegacyState.self, from: fileName) {
            accentHex = legacy.accentHex
            soundEnabled = legacy.soundEnabled
            exportPlaceholderEnabled = legacy.exportPlaceholderEnabled
            iCloudSyncEnabled = false
            syncFolderBookmark = nil
            syncFolderDisplayName = nil
            lastSuccessfulSyncAt = nil
            lastModifiedAt = defaultModifiedAt
        } else {
            accentHex = "#FF7A2F"
            soundEnabled = true
            exportPlaceholderEnabled = false
            iCloudSyncEnabled = false
            syncFolderBookmark = nil
            syncFolderDisplayName = nil
            lastSuccessfulSyncAt = nil
            lastModifiedAt = defaultModifiedAt
        }

        persist()
    }

    var accentColor: Color {
        Color(hex: accentHex) ?? Color.orange
    }

    func cloudSnapshot() -> CloudSnapshot {
        CloudSnapshot(
            accentHex: accentHex,
            soundEnabled: soundEnabled,
            exportPlaceholderEnabled: exportPlaceholderEnabled,
            modifiedAt: lastModifiedAt
        )
    }

    func applyCloudSnapshot(_ snapshot: CloudSnapshot) {
        guard snapshot.modifiedAt > lastModifiedAt else { return }

        isApplyingCloudSnapshot = true
        accentHex = snapshot.accentHex
        soundEnabled = snapshot.soundEnabled
        exportPlaceholderEnabled = snapshot.exportPlaceholderEnabled
        lastModifiedAt = snapshot.modifiedAt
        isApplyingCloudSnapshot = false
        persist()
    }

    func updateLastSuccessfulSync(_ date: Date) {
        lastSuccessfulSyncAt = date
        persist()
    }

    var hasSyncFolder: Bool {
        syncFolderBookmark != nil
    }

    @discardableResult
    func updateSyncFolder(url: URL) -> Bool {
        do {
            let bookmark = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            syncFolderBookmark = bookmark
            syncFolderDisplayName = url.lastPathComponent
            persist()
            onDataChanged?()
            return true
        } catch {
            return false
        }
    }

    func clearSyncFolder() {
        syncFolderBookmark = nil
        syncFolderDisplayName = nil
        persist()
        onDataChanged?()
    }

    func resolveSyncFolderURL() -> URL? {
        guard let bookmark = syncFolderBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if isStale, let refreshed = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            syncFolderBookmark = refreshed
            persist()
        }

        return url
    }

    private func handleSyncedPreferenceMutation() {
        guard isApplyingCloudSnapshot == false else { return }
        lastModifiedAt = Date()
        persist()
        onDataChanged?()
    }

    private func persist() {
        storage.save(
            State(
                accentHex: accentHex,
                soundEnabled: soundEnabled,
                exportPlaceholderEnabled: exportPlaceholderEnabled,
                iCloudSyncEnabled: iCloudSyncEnabled,
                syncFolderBookmark: syncFolderBookmark,
                syncFolderDisplayName: syncFolderDisplayName,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
                lastModifiedAt: lastModifiedAt
            ),
            to: fileName
        )
    }
}
