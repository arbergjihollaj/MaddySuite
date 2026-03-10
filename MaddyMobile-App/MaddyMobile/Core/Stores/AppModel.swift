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
            case .checking: return "Checking Sync"
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
                return "Validating configured sync channels."
            case .active:
                return "Your data syncs while staying available offline."
            case .syncing:
                return "Merging local, backend, and folder data."
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
    let calendarStore: CalendarStore

    @Published private(set) var syncStatus: SyncStatus = .checking

    var lastSuccessfulSyncAt: Date? {
        settingsStore.lastSuccessfulSyncAt
    }

    var syncFolderDisplayName: String {
        settingsStore.syncFolderDisplayName ?? "No folder selected"
    }

    private let storage: LocalJSONStorage
    private var pendingSyncTask: Task<Void, Never>?
    private var periodicSyncTask: Task<Void, Never>?
    private var dailyLoopTask: Task<Void, Never>?
    private var isSyncing = false
    private var backendTaskSyncState: BackendTaskSyncState

    private let backendTaskSyncMetaFile = "backend_task_sync_meta.json"

    init(storage: LocalJSONStorage = .shared) {
        self.storage = storage
        settingsStore = SettingsStore(storage: storage)
        tasksStore = TasksStore(storage: storage)
        habitStore = HabitStore(storage: storage)
        focusStore = FocusStore(storage: storage)
        gamificationStore = GamificationStore(storage: storage)
        calendarStore = CalendarStore(settingsStore: settingsStore, tasksStore: tasksStore)
        backendTaskSyncState = storage.load(BackendTaskSyncState.self, from: backendTaskSyncMetaFile, fallback: .empty)

        wire()
        startPeriodicSyncLoop()
        startDailyLoop()

        Task { [weak self] in
            await self?.bootstrapSync()
        }
    }

    deinit {
        pendingSyncTask?.cancel()
        periodicSyncTask?.cancel()
        dailyLoopTask?.cancel()
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
        if settingsStore.backendSyncEnabled {
            scheduleSync(immediate: true)
        } else {
            syncStatus = .unavailable("Select an iCloud Drive folder to enable sync.")
        }
    }

    private func wire() {
        tasksStore.onTaskCompleted = { [weak self] task, completedToday in
            self?.gamificationStore.registerTaskCompletion(task: task, completedToday: completedToday)
        }
        tasksStore.onDailyTaskMissed = { [weak self] task in
            self?.gamificationStore.registerMissedDailyTask(task)
        }

        habitStore.onHabitCompleted = { [weak self] habit in
            let isRequired = habit.title.lowercased().contains("required") || habit.title.lowercased().contains("must")
            self?.gamificationStore.registerHabitCompletion(habit: habit, isRequired: isRequired)
        }

        focusStore.onSessionRecorded = { [weak self] session in
            guard let self else { return }
            let sessionsToday = self.focusStore.sessions.filter { Calendar.current.isDateInToday($0.startDate) }.count
            let dailyGoalReached = self.focusStore.todayFocusMinutes >= self.focusStore.dailyGoalMinutes
            self.gamificationStore.registerFocusCompletion(
                session: session,
                sessionsToday: sessionsToday,
                dailyGoalReached: dailyGoalReached
            )
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
                self.syncStatus = self.isAnySyncEnabled ? .active : .disabled
            }
        }

        ensureDailyTasksAndSmartSuggestions()
    }

    private func bootstrapSync() async {
        if isAnySyncEnabled == false {
            syncStatus = .disabled
            return
        }

        if settingsStore.iCloudSyncEnabled, settingsStore.hasSyncFolder == false {
            syncStatus = .unavailable("Select an iCloud Drive folder to enable sync.")
            return
        }

        syncStatus = .active
        scheduleSync(immediate: true)
    }

    private func startPeriodicSyncLoop() {
        periodicSyncTask?.cancel()
        periodicSyncTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard let self else { return }
                await self.periodicSyncTick()
            }
        }
    }

    private func periodicSyncTick() async {
        guard isAnySyncEnabled else { return }
        scheduleSync(immediate: true)
    }

    private func startDailyLoop() {
        dailyLoopTask?.cancel()
        dailyLoopTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self else { return }
                await self.dailyLoopTick()
            }
        }
    }

    private func dailyLoopTick() async {
        tasksStore.applyDailyRollover()
        habitStore.applyStreakDecay()
        ensureDailyTasksAndSmartSuggestions()

        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        guard hour == 20, minute <= 2 else { return }

        let dailyTasks = tasksStore.dailyTasks(for: now) + tasksStore.completedDailyTasks(for: now)
        let requiredHabits = habitStore.habits.filter {
            $0.title.lowercased().contains("required") || $0.title.lowercased().contains("must")
        }
        let dayKey = HabitStore.dayKey(now)
        let completedRequired = requiredHabits.filter { ($0.history[dayKey] ?? 0) >= $0.targetValue }.count
        let context = DailyEvaluationContext(
            date: now,
            dailyTasks: dailyTasks,
            requiredHabits: requiredHabits,
            completedRequiredHabitCount: completedRequired,
            focusGoalReached: focusStore.todayFocusMinutes >= focusStore.dailyGoalMinutes,
            completedNormalTaskCount: tasksStore.completedNormalTasksCount(for: now)
        )
        gamificationStore.evaluateDay(context: context)
    }

    private func ensureDailyTasksAndSmartSuggestions() {
        let smart = gamificationStore.generateSmartDailyTasks()
        tasksStore.ensureDailyTaskCapacity(count: settingsStore.dailyTaskCount, templates: smart)
    }

    private func scheduleSync(immediate: Bool) {
        guard isAnySyncEnabled else {
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
        guard isAnySyncEnabled else {
            syncStatus = .disabled
            return
        }

        guard isSyncing == false else { return }
        isSyncing = true
        syncStatus = .syncing
        defer { isSyncing = false }

        var success = false
        var failures: [String] = []

        if settingsStore.backendSyncEnabled {
            let backendSucceeded = await runBackendTaskSync()
            success = success || backendSucceeded
            if backendSucceeded == false {
                failures.append("Backend sync failed")
            }
        }

        if settingsStore.iCloudSyncEnabled {
            let folderSucceeded = await runFolderSyncCycle()
            success = success || folderSucceeded
            if folderSucceeded == false {
                failures.append("Folder sync failed")
            }
        }

        if success {
            settingsStore.updateLastSuccessfulSync(Date())
            syncStatus = .active
        } else {
            syncStatus = .error(failures.first ?? "Sync failed")
        }
    }

    private var isAnySyncEnabled: Bool {
        settingsStore.iCloudSyncEnabled || settingsStore.backendSyncEnabled
    }

    @discardableResult
    private func runFolderSyncCycle() async -> Bool {
        guard let rootURL = settingsStore.resolveSyncFolderURL() else {
            syncStatus = .unavailable("Selected sync folder is no longer accessible.")
            return false
        }

        let hasSecurityScope = rootURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                rootURL.stopAccessingSecurityScopedResource()
            }
        }

        let syncFolder = rootURL

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
                    continue
                }

                for legacyFileName in payload.domain.legacyFileNames {
                    let legacyURL = syncFolder.appendingPathComponent(legacyFileName)
                    if let legacyEnvelope = try loadEnvelope(from: legacyURL, using: decoder) {
                        remotePayloads[payload.domain] = legacyEnvelope
                        break
                    }
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

            return true
        } catch {
            return false
        }
    }

    @discardableResult
    private func runBackendTaskSync() async -> Bool {
        do {
            let baseURL = try normalizedBackendBaseURL(from: settingsStore.backendBaseURL)
            let headers = backendHeaders(clientDeviceID: settingsStore.backendClientDeviceID)

            var cursor = backendTaskSyncState.cursor
            var hasMore = true
            var guardCount = 0

            while hasMore, guardCount < 20 {
                guardCount += 1
                let pull = try await performBackendRequest(
                    baseURL: baseURL,
                    path: "sync/pull?cursor=\(cursor)&limit=200",
                    method: "GET",
                    headers: headers,
                    requestBody: Optional<EmptyBody>.none,
                    responseType: BackendPullResponse.self
                )

                if pull.changes.isEmpty == false {
                    applyBackendTaskChanges(pull.changes)
                }

                cursor = pull.cursor
                hasMore = pull.hasMore
            }

            _ = try await performBackendRequest(
                baseURL: baseURL,
                path: "sync/ack",
                method: "POST",
                headers: headers,
                requestBody: BackendAckRequest(clientDeviceId: settingsStore.backendClientDeviceID, cursor: cursor),
                responseType: BackendAckResponse.self
            )

            let currentPayloads = currentBackendTaskPayloads()
            let currentSignatures = currentPayloads.reduce(into: [String: String]()) { partial, entry in
                partial[entry.id.lowercased()] = backendTaskSignature(for: entry)
            }

            var mutations: [BackendSyncMutation] = []
            for payload in currentPayloads {
                let key = payload.id.lowercased()
                let previous = backendTaskSyncState.taskSignatures[key]
                let next = currentSignatures[key]
                if previous != next {
                    mutations.append(
                        BackendSyncMutation(
                            clientMutationId: "upsert-\(key)-\(Int(payload.clientUpdatedAtDate.timeIntervalSince1970))",
                            entityType: "task",
                            operation: "upsert",
                            entityId: payload.id,
                            timestamp: payload.clientUpdatedAt,
                            payload: payload
                        )
                    )
                }
            }

            for key in backendTaskSyncState.taskSignatures.keys where currentSignatures[key] == nil {
                mutations.append(
                    BackendSyncMutation(
                        clientMutationId: "delete-\(key)",
                        entityType: "task",
                        operation: "delete",
                        entityId: key,
                        timestamp: BackendDateFormatter.shared.string(from: Date()),
                        payload: nil
                    )
                )
            }

            if mutations.isEmpty == false {
                for chunk in mutations.chunked(into: 100) {
                    _ = try await performBackendRequest(
                        baseURL: baseURL,
                        path: "sync/push",
                        method: "POST",
                        headers: headers,
                        requestBody: BackendPushRequest(clientDeviceId: settingsStore.backendClientDeviceID, mutations: chunk),
                        responseType: BackendPushResponse.self
                    )
                }
            }

            backendTaskSyncState.cursor = cursor
            backendTaskSyncState.taskSignatures = currentBackendTaskPayloads().reduce(into: [String: String]()) { partial, entry in
                partial[entry.id.lowercased()] = backendTaskSignature(for: entry)
            }
            persistBackendTaskSyncState()
            return true
        } catch {
            return false
        }
    }

    private func persistBackendTaskSyncState() {
        storage.save(backendTaskSyncState, to: backendTaskSyncMetaFile)
    }

    private func applyBackendTaskChanges(_ changes: [BackendChange]) {
        guard changes.isEmpty == false else { return }

        var snapshot = tasksStore.cloudSnapshot()
        var active = snapshot.tasks
        var archived = snapshot.archivedTasks
        var activeByID = Dictionary(uniqueKeysWithValues: active.enumerated().map { ($0.element.id, $0.offset) })
        var archivedByTaskID = Dictionary(uniqueKeysWithValues: archived.enumerated().map { ($0.element.task.id, $0.offset) })

        for change in changes where change.entityType == "task" {
            guard let payload = change.payload, let task = payload.toTaskItem() else { continue }
            let id = task.id
            let removeTask = change.operation == "deleted" || payload.deletedAt != nil || payload.status == "deleted"

            if removeTask {
                if let index = activeByID[id] {
                    active.remove(at: index)
                    activeByID = Dictionary(uniqueKeysWithValues: active.enumerated().map { ($0.element.id, $0.offset) })
                }
                if let index = archivedByTaskID[id] {
                    archived.remove(at: index)
                    archivedByTaskID = Dictionary(uniqueKeysWithValues: archived.enumerated().map { ($0.element.task.id, $0.offset) })
                }
                continue
            }

            if task.status == .done || task.status == .missed {
                if let index = activeByID[id] {
                    active.remove(at: index)
                    activeByID = Dictionary(uniqueKeysWithValues: active.enumerated().map { ($0.element.id, $0.offset) })
                }
                let archivedEntry = ArchivedTaskItem(
                    id: archived.first(where: { $0.task.id == id })?.id ?? UUID(),
                    task: task,
                    archivedAt: archived.first(where: { $0.task.id == id })?.archivedAt ?? Date()
                )
                if let index = archivedByTaskID[id] {
                    archived[index] = archivedEntry
                } else {
                    archived.insert(archivedEntry, at: 0)
                }
                archivedByTaskID = Dictionary(uniqueKeysWithValues: archived.enumerated().map { ($0.element.task.id, $0.offset) })
            } else {
                if let index = archivedByTaskID[id] {
                    archived.remove(at: index)
                    archivedByTaskID = Dictionary(uniqueKeysWithValues: archived.enumerated().map { ($0.element.task.id, $0.offset) })
                }
                if let index = activeByID[id] {
                    active[index] = task
                } else {
                    active.append(task)
                }
                activeByID = Dictionary(uniqueKeysWithValues: active.enumerated().map { ($0.element.id, $0.offset) })
            }
        }

        snapshot.tasks = active
        snapshot.archivedTasks = archived
        snapshot.modifiedAt = Date()
        tasksStore.applyCloudSnapshot(snapshot)
    }

    private func currentBackendTaskPayloads() -> [BackendTaskPayload] {
        var records: [UUID: TaskItem] = [:]
        for task in tasksStore.tasks {
            records[task.id] = task
        }
        for archived in tasksStore.archivedTasks {
            let candidate = archived.task
            if let existing = records[candidate.id] {
                if candidate.updatedAt > existing.updatedAt {
                    records[candidate.id] = candidate
                }
            } else {
                records[candidate.id] = candidate
            }
        }
        return records.values.map(BackendTaskPayload.init(task:))
    }

    private func backendTaskSignature(for payload: BackendTaskPayload) -> String {
        let duePart = payload.dueAt ?? "-"
        let completedPart = payload.completedAt ?? "-"
        let dailyPart = payload.dailyDateKey ?? "-"
        let tags = payload.tags.sorted().joined(separator: ",")
        let skills = payload.mappedSkills.sorted().joined(separator: ",")
        return [
            payload.id.lowercased(),
            payload.title,
            payload.status,
            payload.difficulty,
            payload.priority,
            duePart,
            completedPart,
            dailyPart,
            tags,
            skills,
            payload.isDailyTask ? "1" : "0",
            payload.isRequiredDailyTask ? "1" : "0",
            payload.clientUpdatedAt
        ].joined(separator: "|")
    }

    private func normalizedBackendBaseURL(from raw: String) throws -> URL {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = "http://127.0.0.1:4000/v1"
        }
        if trimmed.hasPrefix("http://") == false, trimmed.hasPrefix("https://") == false {
            trimmed = "http://\(trimmed)"
        }
        guard var url = URL(string: trimmed) else {
            throw URLError(.badURL)
        }
        if url.path.isEmpty || url.path == "/" {
            url.append(path: "v1")
        }
        return url
    }

    private func backendHeaders(clientDeviceID: String) -> [String: String] {
        [
            "Content-Type": "application/json",
            "x-device-id": clientDeviceID,
            "x-user-id": "00000000-0000-0000-0000-000000000001",
            "x-user-email": "dev@example.com",
        ]
    }

    private func performBackendRequest<RequestBody: Encodable, ResponseBody: Decodable>(
        baseURL: URL,
        path: String,
        method: String,
        headers: [String: String],
        requestBody: RequestBody?,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let split = normalizedPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let pathOnly = String(split.first ?? "")
        let query = split.count > 1 ? String(split[1]) : nil

        var url = baseURL
        for component in pathOnly.split(separator: "/") {
            url.append(path: String(component))
        }
        if let query, query.isEmpty == false {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.percentEncodedQuery = query
            if let queried = components?.url {
                url = queried
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        if let requestBody {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(requestBody)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ResponseBody.self, from: data)
    }

    private func makeLocalPayloads(using encoder: JSONEncoder) throws -> [DomainPayload] {
        let taskSnapshot = tasksStore.cloudSnapshot()
        let habitSnapshot = habitStore.cloudSnapshot()
        let focusSnapshot = focusStore.cloudSnapshot()
        let gameSnapshot = gamificationStore.cloudSnapshot()
        let sharedSettingsSnapshot = settingsStore.sharedSettingsSnapshot()
        let platformSettingsSnapshot = settingsStore.platformSettingsSnapshot()
        let calendarSnapshot = settingsStore.calendarSyncSnapshot()

        return [
            DomainPayload(domain: .tasks, modifiedAt: taskSnapshot.modifiedAt, payloadData: try encoder.encode(macTasksPayload())),
            DomainPayload(domain: .habits, modifiedAt: habitSnapshot.modifiedAt, payloadData: try encoder.encode(macHabitsPayload())),
            DomainPayload(domain: .focus, modifiedAt: focusSnapshot.modifiedAt, payloadData: try encoder.encode(macFocusPayload())),
            DomainPayload(domain: .gamification, modifiedAt: gameSnapshot.modifiedAt, payloadData: try encoder.encode(gameSnapshot)),
            DomainPayload(domain: .sharedSettings, modifiedAt: sharedSettingsSnapshot.modifiedAt, payloadData: try encoder.encode(sharedSettingsSnapshot)),
            DomainPayload(domain: .mobilePlatformSettings, modifiedAt: platformSettingsSnapshot.modifiedAt, payloadData: try encoder.encode(platformSettingsSnapshot)),
            DomainPayload(domain: .calendarSources, modifiedAt: calendarSnapshot.modifiedAt, payloadData: try encoder.encode(calendarSnapshot))
        ]
    }

    private func applyRemotePayloads(_ payloads: [SyncDomain: FolderSyncEnvelope], using decoder: JSONDecoder) {
        for (domain, envelope) in payloads {
            do {
                switch domain {
                case .tasks:
                    if let macPayload = try? decoder.decode(MacTasksPayload.self, from: envelope.payloadData) {
                        let snapshot = TasksStore.CloudSnapshot(
                            tasks: macPayload.tasks.map { $0.toMobileTask() },
                            archivedTasks: macPayload.archivedTasks.map { $0.toMobileArchivedTask() },
                            modifiedAt: envelope.modifiedAt
                        )
                        tasksStore.applyCloudSnapshot(snapshot)
                    } else {
                        let snapshot = try decoder.decode(TasksStore.CloudSnapshot.self, from: envelope.payloadData)
                        tasksStore.applyCloudSnapshot(snapshot)
                    }
                case .habits:
                    if let macPayload = try? decoder.decode(MacHabitsPayload.self, from: envelope.payloadData) {
                        let snapshot = HabitStore.CloudSnapshot(
                            habits: macPayload.habits.map { $0.toMobileHabit() },
                            modifiedAt: envelope.modifiedAt
                        )
                        habitStore.applyCloudSnapshot(snapshot)
                    } else {
                        let snapshot = try decoder.decode(HabitStore.CloudSnapshot.self, from: envelope.payloadData)
                        habitStore.applyCloudSnapshot(snapshot)
                    }
                case .focus:
                    if let macPayload = try? decoder.decode(MacFocusPayload.self, from: envelope.payloadData) {
                        let sessions = macPayload.logs.map { $0.toMobileSession() }
                        let snapshot = FocusStore.CloudSnapshot(
                            selectedMode: focusStore.selectedMode,
                            customMinutes: focusStore.customMinutes,
                            dailyGoalMinutes: focusStore.dailyGoalMinutes,
                            sessions: sessions,
                            modifiedAt: envelope.modifiedAt
                        )
                        focusStore.applyCloudSnapshot(snapshot)
                    } else {
                        let snapshot = try decoder.decode(FocusStore.CloudSnapshot.self, from: envelope.payloadData)
                        focusStore.applyCloudSnapshot(snapshot)
                    }
                case .gamification:
                    let snapshot = try decoder.decode(GamificationStore.CloudSnapshot.self, from: envelope.payloadData)
                    gamificationStore.applyCloudSnapshot(snapshot)
                case .sharedSettings:
                    if let shared = try? decoder.decode(SettingsStore.SharedSettingsSnapshot.self, from: envelope.payloadData) {
                        settingsStore.applySharedSettingsSnapshot(shared)
                    } else if let legacyMobile = try? decoder.decode(SettingsStore.CloudSnapshot.self, from: envelope.payloadData) {
                        settingsStore.applySharedSettingsSnapshot(
                            SettingsStore.SharedSettingsSnapshot(
                                accentHex: legacyMobile.accentHex,
                                soundEnabled: legacyMobile.soundEnabled,
                                dailyTaskCount: min(8, max(1, legacyMobile.dailyTaskCount ?? settingsStore.dailyTaskCount)),
                                dailySummaryEnabled: legacyMobile.dailySummaryEnabled ?? settingsStore.dailySummaryEnabled,
                                modifiedAt: legacyMobile.modifiedAt
                            )
                        )
                    } else if let legacyMac = try? decoder.decode(MacLegacySettingsPayload.self, from: envelope.payloadData) {
                        settingsStore.applySharedSettingsSnapshot(
                            SettingsStore.SharedSettingsSnapshot(
                                accentHex: legacyMac.snapshot.accentHex,
                                soundEnabled: legacyMac.snapshot.focusSoundEnabled,
                                dailyTaskCount: min(8, max(1, legacyMac.snapshot.dailyTaskCount)),
                                dailySummaryEnabled: legacyMac.snapshot.dailySummaryEnabled,
                                modifiedAt: envelope.modifiedAt
                            )
                        )
                    }
                case .mobilePlatformSettings:
                    if let platform = try? decoder.decode(SettingsStore.PlatformSettingsSnapshot.self, from: envelope.payloadData) {
                        settingsStore.applyPlatformSettingsSnapshot(platform)
                    } else if let legacyMobile = try? decoder.decode(SettingsStore.CloudSnapshot.self, from: envelope.payloadData) {
                        settingsStore.applyCloudSnapshot(legacyMobile)
                    }
                case .calendarSources:
                    let snapshot = try decoder.decode(SettingsStore.CalendarSyncSnapshot.self, from: envelope.payloadData)
                    settingsStore.applyCalendarSyncSnapshot(snapshot)
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

    private func macTasksPayload() -> MacTasksPayload {
        let snapshot = tasksStore.cloudSnapshot()
        return MacTasksPayload(
            tasks: snapshot.tasks.map(MacTaskItem.init(from:)),
            archivedTasks: snapshot.archivedTasks.map(MacArchivedTaskItem.init(from:))
        )
    }

    private func macHabitsPayload() -> MacHabitsPayload {
        let snapshot = habitStore.cloudSnapshot()
        return MacHabitsPayload(habits: snapshot.habits.map(MacHabitItem.init(from:)))
    }

    private func macFocusPayload() -> MacFocusPayload {
        let snapshot = focusStore.cloudSnapshot()
        return MacFocusPayload(logs: snapshot.sessions.map(MacFocusLogEntry.init(from:)))
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
    case sharedSettings
    case mobilePlatformSettings
    case calendarSources

    var fileName: String {
        switch self {
        case .tasks:
            return "mac_tasks_sync.json"
        case .habits:
            return "mac_habits_sync.json"
        case .focus:
            return "mac_focus_sync.json"
        case .gamification:
            return "mac_gamification_sync.json"
        case .sharedSettings:
            return "shared_settings_sync.json"
        case .mobilePlatformSettings:
            return "mobile_platform_settings_sync.json"
        case .calendarSources:
            return "calendar_sources_sync.json"
        }
    }

    var legacyFileNames: [String] {
        switch self {
        case .sharedSettings:
            return ["mac_settings_sync.json"]
        case .mobilePlatformSettings:
            return ["mobile_settings_sync.json"]
        default:
            return []
        }
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

// =====================================================
// MARK: - Mac Sync Compat
// [TAG: MOBILE_MAC_SYNC_COMPAT]
// =====================================================

private struct MacTasksPayload: Codable {
    var tasks: [MacTaskItem]
    var archivedTasks: [MacArchivedTaskItem]
}

private enum MacTaskPriority: String, Codable {
    case high
    case medium
    case low
}

private enum MacTaskRecurrence: String, Codable {
    case none
    case daily
    case weekly
    case monthly
}

private struct MacTaskItem: Codable {
    var id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var priority: MacTaskPriority
    var tags: [String]
    var status: TaskStatus
    var recurrence: MacTaskRecurrence
    var order: Int
    var createdAt: Date
    var completedAt: Date?

    init(from task: TaskItem) {
        self.id = task.id
        self.title = task.title
        self.notes = ""
        self.dueDate = task.dueDate
        switch task.priority {
        case .low: self.priority = .low
        case .medium: self.priority = .medium
        case .high: self.priority = .high
        }
        self.tags = task.tags
        self.status = task.status
        self.recurrence = .none
        self.order = 0
        self.createdAt = task.createdAt
        self.completedAt = task.completedAt
    }

    func toMobileTask() -> TaskItem {
        let updatedAt = max(createdAt, completedAt ?? createdAt)
        let mappedPriority: TaskPriority
        switch priority {
        case .low: mappedPriority = .low
        case .medium: mappedPriority = .medium
        case .high: mappedPriority = .high
        }
        return TaskItem(
            id: id,
            title: title,
            dueDate: dueDate,
            tags: tags,
            status: status,
            difficulty: .medium,
            priority: mappedPriority,
            mappedSkills: [.execution],
            isDailyTask: false,
            isRequiredDailyTask: false,
            dailyDateKey: nil,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt
        )
    }
}

private struct MacArchivedTaskItem: Codable {
    var id: UUID
    var task: MacTaskItem
    var archivedAt: Date
    var sourceStatus: TaskStatus

    init(from item: ArchivedTaskItem) {
        self.id = item.id
        self.task = MacTaskItem(from: item.task)
        self.archivedAt = item.archivedAt
        self.sourceStatus = item.task.status
    }

    func toMobileArchivedTask() -> ArchivedTaskItem {
        ArchivedTaskItem(
            id: id,
            task: task.toMobileTask(),
            archivedAt: archivedAt
        )
    }
}

private struct MacHabitsPayload: Codable {
    var habits: [MacHabitItem]
}

private enum MacHabitKind: String, Codable {
    case timeBased
    case quantityBased
}

private struct MacHabitItem: Codable {
    var id: UUID
    var title: String
    var symbol: String
    var accentHex: String
    var kind: MacHabitKind
    var targetPerDay: Int
    var tags: [String]
    var scheduledWeekdays: [Int]
    var history: [String: Int]

    init(from habit: Habit) {
        self.id = habit.id
        self.title = habit.title
        self.symbol = habit.symbol
        self.accentHex = habit.colorHex
        self.kind = habit.goalKind == .timeBased ? .timeBased : .quantityBased
        self.targetPerDay = max(1, habit.targetValue)
        self.tags = []
        self.scheduledWeekdays = habit.scheduleMode == .weekdays ? habit.weekdays : [2, 3, 4, 5, 6]
        self.history = habit.history
    }

    func toMobileHabit() -> Habit {
        let streak = history.keys.sorted().count
        let latestKey = history.keys.sorted().last
        return Habit(
            id: id,
            title: title,
            symbol: symbol,
            colorHex: accentHex,
            goalKind: kind == .timeBased ? .timeBased : .quantityBased,
            targetValue: max(1, targetPerDay),
            scheduleMode: .weekdays,
            weekdays: scheduledWeekdays.isEmpty ? [2, 3, 4, 5, 6] : scheduledWeekdays,
            everyXDays: 1,
            streak: max(0, streak),
            lastCompletedDateKey: latestKey,
            history: history
        )
    }
}

private struct MacFocusPayload: Codable {
    var logs: [MacFocusLogEntry]
}

private struct MacFocusLogEntry: Codable {
    var id: UUID
    var phase: String
    var startedAt: Date
    var durationSeconds: Int
    var source: String

    init(from session: FocusSession) {
        self.id = session.id
        self.phase = session.mode == .custom ? "custom" : "work"
        self.startedAt = session.startDate
        self.durationSeconds = max(60, session.durationMinutes * 60)
        self.source = "mobile"
    }

    func toMobileSession() -> FocusSession {
        let seconds = max(60, durationSeconds)
        let minutes = max(1, Int(round(Double(seconds) / 60.0)))
        return FocusSession(
            id: id,
            startDate: startedAt,
            endDate: startedAt.addingTimeInterval(TimeInterval(seconds)),
            durationMinutes: minutes,
            mode: phase == "custom" ? .custom : .pomodoro
        )
    }
}

private struct MacLegacySettingsPayload: Codable {
    var snapshot: MacLegacySettingsSnapshot
}

private struct MacLegacySettingsSnapshot: Codable {
    var accentHex: String
    var focusSoundEnabled: Bool
    var dailyTaskCount: Int
    var dailySummaryEnabled: Bool
}

private struct BackendTaskSyncState: Codable {
    var cursor: String
    var taskSignatures: [String: String]

    static let empty = BackendTaskSyncState(cursor: "0", taskSignatures: [:])
}

private struct BackendPushRequest: Codable {
    var clientDeviceId: String
    var mutations: [BackendSyncMutation]
}

private struct BackendAckRequest: Codable {
    var clientDeviceId: String
    var cursor: String
}

private struct BackendPushResponse: Codable {
    var accepted: Int?
}

private struct BackendAckResponse: Codable {
    var cursor: String
}

private struct BackendPullResponse: Codable {
    var cursor: String
    var hasMore: Bool
    var changes: [BackendChange]
}

private struct BackendChange: Codable {
    var entityType: String
    var operation: String
    var payload: BackendTaskEntity?
}

private struct BackendSyncMutation: Codable {
    var clientMutationId: String
    var entityType: String
    var operation: String
    var entityId: String?
    var timestamp: String
    var payload: BackendTaskPayload?
}

private struct BackendTaskPayload: Codable {
    var id: String
    var title: String
    var dueAt: String?
    var tags: [String]
    var status: String
    var difficulty: String
    var priority: String
    var mappedSkills: [String]
    var isDailyTask: Bool
    var isRequiredDailyTask: Bool
    var dailyDateKey: String?
    var completedAt: String?
    var clientUpdatedAt: String

    init(task: TaskItem) {
        id = task.id.uuidString.lowercased()
        title = task.title
        dueAt = task.dueDate.map { BackendDateFormatter.shared.string(from: $0) }
        tags = task.tags
        status = task.status.rawValue
        difficulty = task.difficulty.rawValue
        priority = task.priority.rawValue
        mappedSkills = task.mappedSkills.map(\.rawValue)
        isDailyTask = task.isDailyTask
        isRequiredDailyTask = task.isRequiredDailyTask
        dailyDateKey = task.dailyDateKey
        completedAt = task.completedAt.map { BackendDateFormatter.shared.string(from: $0) }
        clientUpdatedAt = BackendDateFormatter.shared.string(from: task.updatedAt)
    }

    var clientUpdatedAtDate: Date {
        BackendDateFormatter.date(from: clientUpdatedAt) ?? Date()
    }
}

private struct BackendTaskEntity: Codable {
    var id: String?
    var title: String?
    var dueAt: String?
    var tags: [String]?
    var status: String?
    var difficulty: String?
    var priority: String?
    var mappedSkills: [String]?
    var isDailyTask: Bool?
    var isRequiredDailyTask: Bool?
    var dailyDateKey: String?
    var completedAt: String?
    var deletedAt: String?
    var clientUpdatedAt: String?
    var createdAt: String?
    var updatedAt: String?

    func toTaskItem() -> TaskItem? {
        guard let id, let uuid = UUID(uuidString: id) else { return nil }

        let resolvedStatus = TaskStatus(rawValue: status ?? TaskStatus.backlog.rawValue) ?? .backlog
        let resolvedDifficulty = TaskDifficulty(rawValue: difficulty ?? TaskDifficulty.medium.rawValue) ?? .medium
        let resolvedPriority = TaskPriority(rawValue: priority ?? TaskPriority.medium.rawValue) ?? .medium
        let resolvedSkills = (mappedSkills ?? []).compactMap(TaskSkillTag.init(rawValue:))
        let created = createdAt.flatMap { BackendDateFormatter.date(from: $0) } ?? Date()
        let updated = clientUpdatedAt.flatMap { BackendDateFormatter.date(from: $0) }
            ?? updatedAt.flatMap { BackendDateFormatter.date(from: $0) }
            ?? created

        return TaskItem(
            id: uuid,
            title: title ?? "",
            dueDate: dueAt.flatMap { BackendDateFormatter.date(from: $0) },
            tags: tags ?? [],
            status: resolvedStatus,
            difficulty: resolvedDifficulty,
            priority: resolvedPriority,
            mappedSkills: resolvedSkills.isEmpty ? [.execution] : resolvedSkills,
            isDailyTask: isDailyTask ?? false,
            isRequiredDailyTask: isRequiredDailyTask ?? false,
            dailyDateKey: dailyDateKey,
            createdAt: created,
            updatedAt: updated,
            completedAt: completedAt.flatMap { BackendDateFormatter.date(from: $0) }
        )
    }
}

private enum BackendDateFormatter {
    static let shared: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let fallback: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from value: String) -> Date? {
        shared.date(from: value) ?? fallback.date(from: value)
    }
}

private struct EmptyBody: Codable {}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var result: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(Array(self[index..<end]))
            index = end
        }
        return result
    }
}
