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
    let calendarStore: CalendarStore

    @Published private(set) var syncStatus: SyncStatus = .checking

    var lastSuccessfulSyncAt: Date? {
        settingsStore.lastSuccessfulSyncAt
    }

    var syncFolderDisplayName: String {
        settingsStore.syncFolderDisplayName ?? "No folder selected"
    }

    private var pendingSyncTask: Task<Void, Never>?
    private var periodicSyncTask: Task<Void, Never>?
    private var dailyLoopTask: Task<Void, Never>?
    private var isSyncing = false

    init(storage: LocalJSONStorage = .shared) {
        settingsStore = SettingsStore(storage: storage)
        tasksStore = TasksStore(storage: storage)
        habitStore = HabitStore(storage: storage)
        focusStore = FocusStore(storage: storage)
        gamificationStore = GamificationStore(storage: storage)
        calendarStore = CalendarStore(settingsStore: settingsStore, tasksStore: tasksStore)

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
        syncStatus = .unavailable("Select an iCloud Drive folder to enable sync.")
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
                self.syncStatus = .disabled
            }
        }

        ensureDailyTasksAndSmartSuggestions()
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
        guard settingsStore.iCloudSyncEnabled else { return }
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
        let calendarSnapshot = settingsStore.calendarSyncSnapshot()

        return [
            DomainPayload(domain: .tasks, modifiedAt: taskSnapshot.modifiedAt, payloadData: try encoder.encode(macTasksPayload())),
            DomainPayload(domain: .habits, modifiedAt: habitSnapshot.modifiedAt, payloadData: try encoder.encode(macHabitsPayload())),
            DomainPayload(domain: .focus, modifiedAt: focusSnapshot.modifiedAt, payloadData: try encoder.encode(macFocusPayload())),
            DomainPayload(domain: .gamification, modifiedAt: gameSnapshot.modifiedAt, payloadData: try encoder.encode(gameSnapshot)),
            DomainPayload(domain: .settings, modifiedAt: settingsSnapshot.modifiedAt, payloadData: try encoder.encode(settingsSnapshot)),
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
                case .settings:
                    let snapshot = try decoder.decode(SettingsStore.CloudSnapshot.self, from: envelope.payloadData)
                    settingsStore.applyCloudSnapshot(snapshot)
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
    case settings
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
        case .settings:
            return "mobile_settings_sync.json"
        case .calendarSources:
            return "calendar_sources_sync.json"
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
