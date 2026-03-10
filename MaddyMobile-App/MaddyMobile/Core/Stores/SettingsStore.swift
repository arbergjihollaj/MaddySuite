import Foundation
import SwiftUI

// =====================================================
// MARK: - SettingsStore
// [TAG: MOBILE_SETTINGS_STORE]
// =====================================================

enum MobileTab: String, CaseIterable, Codable, Hashable, Identifiable {
    case home
    case focus
    case tasks
    case habits
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .focus: return "Focus"
        case .tasks: return "Tasks"
        case .habits: return "Habits"
        case .more: return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .focus: return "timer"
        case .tasks: return "checklist"
        case .habits: return "flame"
        case .more: return "ellipsis.circle"
        }
    }

    var isAlwaysVisible: Bool {
        self == .home || self == .more
    }

    static var orderedCases: [MobileTab] {
        [.home, .focus, .tasks, .habits, .more]
    }

    static var customizableCases: [MobileTab] {
        orderedCases.filter { $0.isAlwaysVisible == false }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    struct State: Codable {
        var accentHex: String
        var soundEnabled: Bool
        var exportPlaceholderEnabled: Bool
        var dailyTaskCount: Int?
        var dailySummaryEnabled: Bool?
        var iCloudSyncEnabled: Bool
        var syncFolderBookmark: Data?
        var syncFolderDisplayName: String?
        var lastSuccessfulSyncAt: Date?
        var lastModifiedAt: Date?
        var showGoogleCalendarEvents: Bool?
        var showICalCalendarEvents: Bool?
        var showTaskCalendarEntries: Bool?
        var iCalSubscriptions: [ICalSubscription]?
        var visibleTabRawValues: [String]?
        var backendSyncEnabled: Bool?
        var backendBaseURL: String?
        var backendClientDeviceID: String?
    }

    struct CloudSnapshot: Codable {
        var accentHex: String
        var soundEnabled: Bool
        var exportPlaceholderEnabled: Bool
        var dailyTaskCount: Int?
        var dailySummaryEnabled: Bool?
        var modifiedAt: Date
        var showGoogleCalendarEvents: Bool?
        var showICalCalendarEvents: Bool?
        var showTaskCalendarEntries: Bool?
        var visibleTabRawValues: [String]?
        var backendSyncEnabled: Bool?
        var backendBaseURL: String?
        var backendClientDeviceID: String?
    }

    struct SharedSettingsSnapshot: Codable {
        var accentHex: String
        var soundEnabled: Bool
        var dailyTaskCount: Int
        var dailySummaryEnabled: Bool
        var modifiedAt: Date
    }

    struct PlatformSettingsSnapshot: Codable {
        var exportPlaceholderEnabled: Bool
        var visibleTabRawValues: [String]
        var backendSyncEnabled: Bool
        var backendBaseURL: String
        var backendClientDeviceID: String
        var modifiedAt: Date

        enum CodingKeys: String, CodingKey {
            case exportPlaceholderEnabled
            case visibleTabRawValues
            case backendSyncEnabled
            case backendBaseURL
            case backendClientDeviceID
            case modifiedAt
        }

        init(
            exportPlaceholderEnabled: Bool,
            visibleTabRawValues: [String],
            backendSyncEnabled: Bool,
            backendBaseURL: String,
            backendClientDeviceID: String,
            modifiedAt: Date
        ) {
            self.exportPlaceholderEnabled = exportPlaceholderEnabled
            self.visibleTabRawValues = visibleTabRawValues
            self.backendSyncEnabled = backendSyncEnabled
            self.backendBaseURL = backendBaseURL
            self.backendClientDeviceID = backendClientDeviceID
            self.modifiedAt = modifiedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            exportPlaceholderEnabled = try c.decodeIfPresent(Bool.self, forKey: .exportPlaceholderEnabled) ?? false
            visibleTabRawValues = try c.decodeIfPresent([String].self, forKey: .visibleTabRawValues) ?? MobileTab.orderedCases.map(\.rawValue)
            backendSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .backendSyncEnabled) ?? false
            backendBaseURL = try c.decodeIfPresent(String.self, forKey: .backendBaseURL) ?? "http://127.0.0.1:4000/v1"
            backendClientDeviceID = try c.decodeIfPresent(String.self, forKey: .backendClientDeviceID) ?? "mobile-\(UUID().uuidString.lowercased())"
            modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
        }
    }

    struct CalendarSyncSnapshot: Codable {
        var iCalSubscriptions: [ICalSubscription]
        var showGoogleCalendarEvents: Bool
        var showICalCalendarEvents: Bool
        var showTaskCalendarEntries: Bool
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

    @Published var dailyTaskCount: Int {
        didSet {
            guard isApplyingCloudSnapshot == false else { return }
            dailyTaskCount = min(8, max(1, dailyTaskCount))
            handleSyncedPreferenceMutation()
        }
    }

    @Published var dailySummaryEnabled: Bool {
        didSet { handleSyncedPreferenceMutation() }
    }

    @Published var iCloudSyncEnabled: Bool {
        didSet {
            guard isApplyingCloudSnapshot == false else { return }
            persist()
            onICloudSyncPreferenceChanged?(iCloudSyncEnabled)
        }
    }

    @Published var backendSyncEnabled: Bool {
        didSet { handleSyncedPreferenceMutation() }
    }

    @Published var backendBaseURL: String {
        didSet { handleSyncedPreferenceMutation() }
    }

    @Published var backendClientDeviceID: String {
        didSet { handleSyncedPreferenceMutation() }
    }

    @Published var showGoogleCalendarEvents: Bool {
        didSet { handleSyncedPreferenceMutation() }
    }

    @Published var showICalCalendarEvents: Bool {
        didSet { handleSyncedPreferenceMutation() }
    }

    @Published var showTaskCalendarEntries: Bool {
        didSet { handleSyncedPreferenceMutation() }
    }

    @Published var iCalSubscriptions: [ICalSubscription] {
        didSet { handleSyncedPreferenceMutation() }
    }

    @Published private var visibleTabRawValues: [String] {
        didSet {
            guard isApplyingCloudSnapshot == false else { return }
            let normalized = Self.normalizedVisibleTabRawValues(visibleTabRawValues)
            if normalized != visibleTabRawValues {
                visibleTabRawValues = normalized
                return
            }
            handleSyncedPreferenceMutation()
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
            dailyTaskCount = min(8, max(1, loaded.dailyTaskCount ?? 3))
            dailySummaryEnabled = loaded.dailySummaryEnabled ?? true
            iCloudSyncEnabled = loaded.iCloudSyncEnabled
            syncFolderBookmark = loaded.syncFolderBookmark
            syncFolderDisplayName = loaded.syncFolderDisplayName
            lastSuccessfulSyncAt = loaded.lastSuccessfulSyncAt
            lastModifiedAt = loaded.lastModifiedAt ?? defaultModifiedAt
            showGoogleCalendarEvents = loaded.showGoogleCalendarEvents ?? true
            showICalCalendarEvents = loaded.showICalCalendarEvents ?? true
            showTaskCalendarEntries = loaded.showTaskCalendarEntries ?? true
            iCalSubscriptions = loaded.iCalSubscriptions ?? []
            visibleTabRawValues = Self.normalizedVisibleTabRawValues(loaded.visibleTabRawValues ?? MobileTab.orderedCases.map(\.rawValue))
            backendSyncEnabled = loaded.backendSyncEnabled ?? false
            backendBaseURL = loaded.backendBaseURL ?? "http://127.0.0.1:4000/v1"
            backendClientDeviceID = loaded.backendClientDeviceID ?? "mobile-\(UUID().uuidString.lowercased())"
        } else if let legacy = storage.loadIfPresent(LegacyState.self, from: fileName) {
            accentHex = legacy.accentHex
            soundEnabled = legacy.soundEnabled
            exportPlaceholderEnabled = legacy.exportPlaceholderEnabled
            dailyTaskCount = 3
            dailySummaryEnabled = true
            iCloudSyncEnabled = true
            syncFolderBookmark = nil
            syncFolderDisplayName = nil
            lastSuccessfulSyncAt = nil
            lastModifiedAt = defaultModifiedAt
            showGoogleCalendarEvents = true
            showICalCalendarEvents = true
            showTaskCalendarEntries = true
            iCalSubscriptions = []
            visibleTabRawValues = MobileTab.orderedCases.map(\.rawValue)
            backendSyncEnabled = false
            backendBaseURL = "http://127.0.0.1:4000/v1"
            backendClientDeviceID = "mobile-\(UUID().uuidString.lowercased())"
        } else {
            accentHex = "#FF7A2F"
            soundEnabled = true
            exportPlaceholderEnabled = false
            dailyTaskCount = 3
            dailySummaryEnabled = true
            iCloudSyncEnabled = true
            syncFolderBookmark = nil
            syncFolderDisplayName = nil
            lastSuccessfulSyncAt = nil
            lastModifiedAt = defaultModifiedAt
            showGoogleCalendarEvents = true
            showICalCalendarEvents = true
            showTaskCalendarEntries = true
            iCalSubscriptions = []
            visibleTabRawValues = MobileTab.orderedCases.map(\.rawValue)
            backendSyncEnabled = false
            backendBaseURL = "http://127.0.0.1:4000/v1"
            backendClientDeviceID = "mobile-\(UUID().uuidString.lowercased())"
        }

        if syncFolderBookmark != nil, iCloudSyncEnabled == false {
            iCloudSyncEnabled = true
        }

        persist()
    }

    var accentColor: Color {
        Color(hex: accentHex) ?? Color.orange
    }

    var visibleTabs: [MobileTab] {
        let allowed = Set(visibleTabRawValues.compactMap(MobileTab.init(rawValue:)))
        return MobileTab.orderedCases.filter { tab in
            tab.isAlwaysVisible || allowed.contains(tab)
        }
    }

    func isTabVisible(_ tab: MobileTab) -> Bool {
        visibleTabs.contains(tab)
    }

    func setTabVisibility(_ tab: MobileTab, isVisible: Bool) {
        guard tab.isAlwaysVisible == false else { return }
        var set = Set(visibleTabRawValues)
        if isVisible {
            set.insert(tab.rawValue)
        } else {
            set.remove(tab.rawValue)
        }
        visibleTabRawValues = Self.normalizedVisibleTabRawValues(Array(set))
    }

    func cloudSnapshot() -> CloudSnapshot {
        CloudSnapshot(
            accentHex: accentHex,
            soundEnabled: soundEnabled,
            exportPlaceholderEnabled: exportPlaceholderEnabled,
            dailyTaskCount: dailyTaskCount,
            dailySummaryEnabled: dailySummaryEnabled,
            modifiedAt: lastModifiedAt,
            showGoogleCalendarEvents: showGoogleCalendarEvents,
            showICalCalendarEvents: showICalCalendarEvents,
            showTaskCalendarEntries: showTaskCalendarEntries,
            visibleTabRawValues: visibleTabRawValues,
            backendSyncEnabled: backendSyncEnabled,
            backendBaseURL: backendBaseURL,
            backendClientDeviceID: backendClientDeviceID
        )
    }

    func sharedSettingsSnapshot() -> SharedSettingsSnapshot {
        SharedSettingsSnapshot(
            accentHex: accentHex,
            soundEnabled: soundEnabled,
            dailyTaskCount: dailyTaskCount,
            dailySummaryEnabled: dailySummaryEnabled,
            modifiedAt: lastModifiedAt
        )
    }

    func applySharedSettingsSnapshot(_ snapshot: SharedSettingsSnapshot) {
        guard snapshot.modifiedAt > lastModifiedAt else { return }

        isApplyingCloudSnapshot = true
        accentHex = snapshot.accentHex
        soundEnabled = snapshot.soundEnabled
        dailyTaskCount = min(8, max(1, snapshot.dailyTaskCount))
        dailySummaryEnabled = snapshot.dailySummaryEnabled
        lastModifiedAt = snapshot.modifiedAt
        isApplyingCloudSnapshot = false
        persist()
    }

    func platformSettingsSnapshot() -> PlatformSettingsSnapshot {
        PlatformSettingsSnapshot(
            exportPlaceholderEnabled: exportPlaceholderEnabled,
            visibleTabRawValues: visibleTabRawValues,
            backendSyncEnabled: backendSyncEnabled,
            backendBaseURL: backendBaseURL,
            backendClientDeviceID: backendClientDeviceID,
            modifiedAt: lastModifiedAt
        )
    }

    func applyPlatformSettingsSnapshot(_ snapshot: PlatformSettingsSnapshot) {
        guard snapshot.modifiedAt > lastModifiedAt else { return }

        isApplyingCloudSnapshot = true
        exportPlaceholderEnabled = snapshot.exportPlaceholderEnabled
        visibleTabRawValues = Self.normalizedVisibleTabRawValues(snapshot.visibleTabRawValues)
        backendSyncEnabled = snapshot.backendSyncEnabled
        backendBaseURL = snapshot.backendBaseURL
        backendClientDeviceID = snapshot.backendClientDeviceID
        lastModifiedAt = snapshot.modifiedAt
        isApplyingCloudSnapshot = false
        persist()
    }

    func applyCloudSnapshot(_ snapshot: CloudSnapshot) {
        guard snapshot.modifiedAt > lastModifiedAt else { return }

        isApplyingCloudSnapshot = true
        accentHex = snapshot.accentHex
        soundEnabled = snapshot.soundEnabled
        exportPlaceholderEnabled = snapshot.exportPlaceholderEnabled
        dailyTaskCount = min(8, max(1, snapshot.dailyTaskCount ?? dailyTaskCount))
        dailySummaryEnabled = snapshot.dailySummaryEnabled ?? dailySummaryEnabled
        showGoogleCalendarEvents = snapshot.showGoogleCalendarEvents ?? showGoogleCalendarEvents
        showICalCalendarEvents = snapshot.showICalCalendarEvents ?? showICalCalendarEvents
        showTaskCalendarEntries = snapshot.showTaskCalendarEntries ?? showTaskCalendarEntries
        visibleTabRawValues = Self.normalizedVisibleTabRawValues(snapshot.visibleTabRawValues ?? visibleTabRawValues)
        backendSyncEnabled = snapshot.backendSyncEnabled ?? backendSyncEnabled
        backendBaseURL = snapshot.backendBaseURL ?? backendBaseURL
        backendClientDeviceID = snapshot.backendClientDeviceID ?? backendClientDeviceID
        lastModifiedAt = snapshot.modifiedAt
        isApplyingCloudSnapshot = false
        persist()
    }

    func calendarSyncSnapshot() -> CalendarSyncSnapshot {
        CalendarSyncSnapshot(
            iCalSubscriptions: iCalSubscriptions,
            showGoogleCalendarEvents: showGoogleCalendarEvents,
            showICalCalendarEvents: showICalCalendarEvents,
            showTaskCalendarEntries: showTaskCalendarEntries,
            modifiedAt: lastModifiedAt
        )
    }

    func applyCalendarSyncSnapshot(_ snapshot: CalendarSyncSnapshot) {
        guard snapshot.modifiedAt > lastModifiedAt else { return }

        isApplyingCloudSnapshot = true
        iCalSubscriptions = snapshot.iCalSubscriptions
        showGoogleCalendarEvents = snapshot.showGoogleCalendarEvents
        showICalCalendarEvents = snapshot.showICalCalendarEvents
        showTaskCalendarEntries = snapshot.showTaskCalendarEntries
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
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

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
            print("[TAG: MOBILE_SYNC_FOLDER_SAVE_FAIL] \(error.localizedDescription)")
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

    // =====================================================
    // MARK: - Calendar Preferences
    // [TAG: MOBILE_CALENDAR_SETTINGS]
    // =====================================================

    @discardableResult
    func addICalSubscription(urlString: String, name: String? = nil) -> Bool {
        let normalized = normalizeSubscriptionURL(urlString)
        guard normalized.isEmpty == false,
              URL(string: normalized) != nil else {
            return false
        }

        if iCalSubscriptions.contains(where: { $0.urlString.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return false
        }

        iCalSubscriptions.append(ICalSubscription.make(urlString: normalized, name: name))
        return true
    }

    func removeICalSubscription(id: UUID) {
        iCalSubscriptions.removeAll { $0.id == id }
    }

    func updateICalSubscriptionEnabled(id: UUID, isEnabled: Bool) {
        guard let index = iCalSubscriptions.firstIndex(where: { $0.id == id }) else { return }
        iCalSubscriptions[index].isEnabled = isEnabled
    }

    func updateICalRefreshMetadata(id: UUID, refreshedAt: Date?, error: String?) {
        guard let index = iCalSubscriptions.firstIndex(where: { $0.id == id }) else { return }
        iCalSubscriptions[index].lastRefreshAt = refreshedAt ?? iCalSubscriptions[index].lastRefreshAt
        iCalSubscriptions[index].lastError = error
    }

    func regenerateBackendClientDeviceID() {
        backendClientDeviceID = "mobile-\(UUID().uuidString.lowercased())"
    }

    private func normalizeSubscriptionURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        if trimmed.lowercased().hasPrefix("webcal://") {
            return "https://" + trimmed.dropFirst("webcal://".count)
        }
        return trimmed
    }

    private func handleSyncedPreferenceMutation() {
        guard isApplyingCloudSnapshot == false else { return }
        lastModifiedAt = Date()
        persist()
        onDataChanged?()
    }

    private static func normalizedVisibleTabRawValues(_ values: [String]) -> [String] {
        var allowed = Set(values)
        for required in MobileTab.orderedCases where required.isAlwaysVisible {
            allowed.insert(required.rawValue)
        }
        return MobileTab.orderedCases
            .map(\.rawValue)
            .filter { allowed.contains($0) }
    }

    private func persist() {
        storage.save(
            State(
                accentHex: accentHex,
                soundEnabled: soundEnabled,
                exportPlaceholderEnabled: exportPlaceholderEnabled,
                dailyTaskCount: dailyTaskCount,
                dailySummaryEnabled: dailySummaryEnabled,
                iCloudSyncEnabled: iCloudSyncEnabled,
                syncFolderBookmark: syncFolderBookmark,
                syncFolderDisplayName: syncFolderDisplayName,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
                lastModifiedAt: lastModifiedAt,
                showGoogleCalendarEvents: showGoogleCalendarEvents,
                showICalCalendarEvents: showICalCalendarEvents,
                showTaskCalendarEntries: showTaskCalendarEntries,
                iCalSubscriptions: iCalSubscriptions,
                visibleTabRawValues: visibleTabRawValues,
                backendSyncEnabled: backendSyncEnabled,
                backendBaseURL: backendBaseURL,
                backendClientDeviceID: backendClientDeviceID
            ),
            to: fileName
        )
    }
}
