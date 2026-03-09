import Foundation

// =====================================================
// MARK: - AppModel
// [TAG: MOBILE_APP_MODEL]
// =====================================================

@MainActor
final class AppModel: ObservableObject {
    enum SyncStatus: Equatable {
        case checking
        case active
        case syncing
        case unavailable(String)
        case disabled
        case error(String)

        var title: String {
            switch self {
            case .checking: return "Checking Folder Sync"
            case .active: return "Sync Active"
            case .syncing: return "Syncing"
            case .unavailable: return "Folder Unavailable"
            case .disabled: return "Local Only"
            case .error: return "Sync Issue"
            }
        }

        var subtitle: String {
            switch self {
            case .checking:
                return "Validating your shared iCloud Drive folder."
            case .active:
                return "Your data syncs through JSON files while staying available offline."
            case .syncing:
                return "Merging local and folder data."
            case .unavailable(let message):
                return message
            case .disabled:
                return "Folder sync is disabled. All data remains stored locally."
            case let .error(message):
                return message
            }
        }

        var iconName: String {
            switch self {
            case .checking: return "folder.badge.questionmark"
            case .active: return "folder.badge.checkmark"
            case .syncing: return "arrow.triangle.2.circlepath"
            case .unavailable: return "folder.badge.exclamationmark"
            case .disabled: return "folder.badge.minus"
            case .error: return "exclamationmark.triangle"
            }
        }
    }

    let settingsStore: SettingsStore
    let tasksStore: TasksStore
    let habitStore: HabitStore
    let focusStore: FocusStore
    let gamificationStore: GamificationStore

    @Published private(set) var syncStatus: SyncStatus = .checking

    var lastSuccessfulSyncAt: Date? {
        settingsStore.lastSuccessfulSyncAt
    }

    var syncFolderDisplayName: String {
        settingsStore.syncFolderDisplayName ?? "No folder selected"
    }

    private var pendingSyncTask: Task<Void, Never>?
    private var isSyncing = false

    init(storage: LocalJSONStorage = .shared) {
        settingsStore = SettingsStore(storage: storage)
        tasksStore = TasksStore(storage: storage)
        habitStore = HabitStore(storage: storage)
        focusStore = FocusStore(storage: storage)
        gamificationStore = GamificationStore(storage: storage)

        wire()

        Task { [weak self] in
            await self?.bootstrapSync()
        }
    }

    func triggerManualSync() {
        scheduleSync(immediate: true)
    }

    @discardableResult
    func setSyncFolder(_ url: URL) -> Bool {
        let success = settingsStore.updateSyncFolder(url: url)
        if success {
            scheduleSync(immediate: true)
        }
        return success
    }

    func clearSyncFolder() {
        settingsStore.clearSyncFolder()
        syncStatus = .unavailable("Select an iCloud Drive folder to enable sync.")
    }

    private func wire() {
        tasksStore.onTaskArchived = { [weak self] _ in
            self?.gamificationStore.registerTaskCompletion()
        }

        habitStore.onHabitCompleted = { [weak self] habit in
            self?.gamificationStore.registerHabitCompletion(streak: habit.streak)
        }

        focusStore.onSessionRecorded = { [weak self] session in
            self?.gamificationStore.registerFocus(minutes: session.durationMinutes)
        }

        let dataChanged: () -> Void = { [weak self] in
            self?.scheduleSync(immediate: false)
        }

        tasksStore.onDataChanged = dataChanged
        habitStore.onDataChanged = dataChanged
        focusStore.onDataChanged = dataChanged
        gamificationStore.onDataChanged = dataChanged
        settingsStore.onDataChanged = dataChanged

        settingsStore.onICloudSyncPreferenceChanged = { [weak self] enabled in
            guard let self else { return }
            if enabled {
                self.scheduleSync(immediate: true)
            } else {
                self.syncStatus = .disabled
            }
        }

        gamificationStore.refreshDailyChallengesIfNeeded()
    }

    private func bootstrapSync() async {
        if settingsStore.iCloudSyncEnabled == false {
            syncStatus = .disabled
            return
        }

        if settingsStore.hasSyncFolder == false {
            syncStatus = .unavailable("Select an iCloud Drive folder to enable sync.")
            return
        }

        syncStatus = .active
        scheduleSync(immediate: true)
    }

    private func scheduleSync(immediate: Bool) {
        guard settingsStore.iCloudSyncEnabled else {
            syncStatus = .disabled
            return
        }

        pendingSyncTask?.cancel()
        pendingSyncTask = Task { [weak self] in
            guard let self else { return }
            if immediate == false {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
            if Task.isCancelled { return }
            await self.performSyncCycle()
        }
    }

    private func performSyncCycle() async {
        guard settingsStore.iCloudSyncEnabled else {
            syncStatus = .disabled
            return
        }

        guard isSyncing == false else { return }
        isSyncing = true
        syncStatus = .syncing
        defer { isSyncing = false }

        guard let rootURL = settingsStore.resolveSyncFolderURL() else {
            syncStatus = .unavailable("Selected sync folder is no longer accessible.")
            return
        }

        let hasSecurityScope = rootURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }

        let syncFolder = rootURL
            .appendingPathComponent("MaddySuiteSync", isDirectory: true)
            .appendingPathComponent("MaddyMobile", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let initialLocalPayloads = try makeLocalPayloads(using: encoder)
            var remotePayloads: [SyncDomain: FolderSyncEnvelope] = [:]

            for payload in initialLocalPayloads {
                let fileURL = syncFolder.appendingPathComponent(payload.domain.fileName)
                if let envelope = try loadEnvelope(from: fileURL, using: decoder) {
                    remotePayloads[payload.domain] = envelope
                }
            }

            applyRemotePayloads(remotePayloads, using: decoder)

            let localPayloads = try makeLocalPayloads(using: encoder)
            for payload in localPayloads {
                let remoteModifiedAt = remotePayloads[payload.domain]?.modifiedAt ?? .distantPast
                guard payload.modifiedAt > remoteModifiedAt || remotePayloads[payload.domain] == nil else { continue }

                let effectiveDate = payload.modifiedAt == .distantPast ? Date() : payload.modifiedAt
                let envelope = FolderSyncEnvelope(modifiedAt: effectiveDate, payloadData: payload.payloadData)
                let fileURL = syncFolder.appendingPathComponent(payload.domain.fileName)
                try saveEnvelope(envelope, to: fileURL, using: encoder)
            }

            settingsStore.updateLastSuccessfulSync(Date())
            syncStatus = .active
        } catch {
            syncStatus = .error("Folder sync failed. Local data remains safe.")
        }
    }

    private func makeLocalPayloads(using encoder: JSONEncoder) throws -> [DomainPayload] {
        let taskSnapshot = tasksStore.cloudSnapshot()
        let habitSnapshot = habitStore.cloudSnapshot()
        let focusSnapshot = focusStore.cloudSnapshot()
        let gameSnapshot = gamificationStore.cloudSnapshot()
        let settingsSnapshot = settingsStore.cloudSnapshot()

        return [
            DomainPayload(domain: .tasks, modifiedAt: taskSnapshot.modifiedAt, payloadData: try encoder.encode(taskSnapshot)),
            DomainPayload(domain: .habits, modifiedAt: habitSnapshot.modifiedAt, payloadData: try encoder.encode(habitSnapshot)),
            DomainPayload(domain: .focus, modifiedAt: focusSnapshot.modifiedAt, payloadData: try encoder.encode(focusSnapshot)),
            DomainPayload(domain: .gamification, modifiedAt: gameSnapshot.modifiedAt, payloadData: try encoder.encode(gameSnapshot)),
            DomainPayload(domain: .settings, modifiedAt: settingsSnapshot.modifiedAt, payloadData: try encoder.encode(settingsSnapshot))
        ]
    }

    private func applyRemotePayloads(_ payloads: [SyncDomain: FolderSyncEnvelope], using decoder: JSONDecoder) {
        for (domain, envelope) in payloads {
            do {
                switch domain {
                case .tasks:
                    let snapshot = try decoder.decode(TasksStore.CloudSnapshot.self, from: envelope.payloadData)
                    tasksStore.applyCloudSnapshot(snapshot)
                case .habits:
                    let snapshot = try decoder.decode(HabitStore.CloudSnapshot.self, from: envelope.payloadData)
                    habitStore.applyCloudSnapshot(snapshot)
                case .focus:
                    let snapshot = try decoder.decode(FocusStore.CloudSnapshot.self, from: envelope.payloadData)
                    focusStore.applyCloudSnapshot(snapshot)
                case .gamification:
                    let snapshot = try decoder.decode(GamificationStore.CloudSnapshot.self, from: envelope.payloadData)
                    gamificationStore.applyCloudSnapshot(snapshot)
                case .settings:
                    let snapshot = try decoder.decode(SettingsStore.CloudSnapshot.self, from: envelope.payloadData)
                    settingsStore.applyCloudSnapshot(snapshot)
                }
            } catch {
                continue
            }
        }
    }

    private func loadEnvelope(from url: URL, using decoder: JSONDecoder) throws -> FolderSyncEnvelope? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(FolderSyncEnvelope.self, from: data)
    }

    private func saveEnvelope(_ envelope: FolderSyncEnvelope, to url: URL, using encoder: JSONEncoder) throws {
        let data = try encoder.encode(envelope)
        try data.write(to: url, options: [.atomic])
    }
}

// =====================================================
// MARK: - Folder Sync Models
// [TAG: MOBILE_FOLDER_SYNC_MODELS]
// =====================================================

private enum SyncDomain: String, CaseIterable {
    case tasks
    case habits
    case focus
    case gamification
    case settings

    var fileName: String {
        "mobile_\(rawValue)_sync.json"
    }
}

private struct DomainPayload {
    let domain: SyncDomain
    let modifiedAt: Date
    let payloadData: Data
}

private struct FolderSyncEnvelope: Codable {
    let modifiedAt: Date
    let payloadData: Data
}
