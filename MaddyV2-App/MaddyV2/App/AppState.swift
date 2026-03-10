//
//  AppState.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI
import Combine
import Foundation
import AppKit

// =====================================================
// MARK: - AppState
// [TAG: V2_APP_STATE]
// =====================================================

@MainActor
final class AppState: ObservableObject {
    @Published var route: AppRoute = .home {
        didSet {
            let next = route.rawValue
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.serialService.sendView(screen: next)
                if self.route == .gamify {
                    self.sendGamifySnapshotToESP(reason: "route changed")
                } else if self.route == .ai {
                    self.sendAIStyleSnapshotToESP(reason: "route changed")
                }
            }
        }
    }

    @Published var settings: MaddySettings {
        didSet {
            let newSettings = settings
            let previousSettings = oldValue
            let calendarSourcesChanged =
                previousSettings.iCalSubscriptions != newSettings.iCalSubscriptions ||
                previousSettings.showGoogleCalendarEvents != newSettings.showGoogleCalendarEvents ||
                previousSettings.showICalCalendarEvents != newSettings.showICalCalendarEvents ||
                previousSettings.showTaskCalendarEntries != newSettings.showTaskCalendarEntries
            persistSettings()
            applyAppearance()
            configureStatisticsAutoExportTimer()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.serialService.setAutoReconnect(enabled: newSettings.autoReconnect)
                self.serialService.preferredPort = newSettings.preferredSerialPort
                self.focusViewModel.dailyGoal = newSettings.dailyFocusGoal
                self.gamificationService.recomputeFocusStreak(
                    from: self.focusViewModel.logs,
                    dailyGoal: newSettings.dailyFocusGoal
                )
                if self.serialService.isConnected {
                    self.sendAIStyleSnapshotToESP(reason: "settings changed")
                }
                let normalizedOrder = Self.normalizedTopOrder(newSettings.topBarOrder)
                if self.topOrder != normalizedOrder {
                    self.topOrder = normalizedOrder
                }
            }

            let syncModeChanged =
                previousSettings.iCloudSyncEnabled != newSettings.iCloudSyncEnabled ||
                previousSettings.backendSyncEnabled != newSettings.backendSyncEnabled
            let backendConfigChanged =
                previousSettings.backendBaseURL != newSettings.backendBaseURL ||
                previousSettings.backendClientDeviceID != newSettings.backendClientDeviceID

            if syncModeChanged {
                if newSettings.iCloudSyncEnabled {
                    if (newSettings.syncFolderPath?.isEmpty ?? true),
                       let defaultFolder = Self.defaultCloudSyncFolderURL(createIfMissing: true) {
                        settings.syncFolderPath = defaultFolder.path
                    }
                }

                if isAnySyncEnabled {
                    scheduleCloudSync(reason: "sync enabled", immediate: true)
                } else {
                    cloudSyncDebounceTask?.cancel()
                    cloudSyncStatus = .disabled
                }
                configureCloudSyncPolling()
            } else if newSettings.backendSyncEnabled, backendConfigChanged {
                scheduleCloudSync(reason: "backend settings updated", immediate: true)
            }

            guard isApplyingCloudSnapshot == false else { return }
            if calendarSourcesChanged {
                markDomainChanged(.calendarSources)
            }
            markDomainChanged(.sharedSettings)
            markDomainChanged(.macPlatformSettings)
            scheduleCloudSync(reason: "settings updated")
        }
    }

    @Published var topOrder: [AppRoute]
    @Published var showMenuBarHint: Bool = false
    @Published private(set) var statisticsLastExportDate: Date?
    @Published private(set) var statisticsLastExportError: String?
    @Published private(set) var cloudSyncStatus: CloudSyncStatus = .checking
    @Published private(set) var cloudSyncLastSuccessfulAt: Date?

    let serialService: SerialService
    let gamificationService: GamificationService
    let aiService: AIService
    let statisticsExportService: StatisticsExportService
    let focusViewModel: FocusViewModel
    let tasksViewModel: TasksViewModel
    let habitsViewModel: HabitsViewModel

    var accentColor: Color {
        Color(hex: settings.accentHex) ?? .orange
    }

    var glassIntensity: Double {
        settings.glassIntensity.clamped(to: 0.15...0.9)
    }

    private let storage: JSONStorageService
    private var cancellables = Set<AnyCancellable>()
    private var clockTimer: AnyCancellable?
    private var statsTimer: AnyCancellable?
    private var dailyLoopTimer: AnyCancellable?
    private var statisticsAutoExportTimer: AnyCancellable?
    private var cloudSyncPollingTimer: AnyCancellable?
    private var appWillTerminateObserver: NSObjectProtocol?
    private var cloudSyncMetadata: CloudSyncMetadata
    private var backendTaskSyncState: BackendTaskSyncState
    private var cloudSyncDebounceTask: Task<Void, Never>?
    private var cloudSyncInFlight = false
    private var isApplyingCloudSnapshot = false

    init(serialService: SerialService) {
        self.storage = JSONStorageService()
        self.serialService = serialService
        self.gamificationService = GamificationService()
        self.aiService = AIService()
        self.statisticsExportService = StatisticsExportService()

        var loadedSettings = storage.load(MaddySettings.self, from: .settings, fallback: .default)
        loadedSettings.topBarOrder = Self.normalizedTopOrder(loadedSettings.topBarOrder)
        Self.bootstrapCloudSyncDefaults(in: &loadedSettings)
        let loadedTasks = storage.load([TaskItem].self, from: .tasks, fallback: [])
        let loadedTaskArchive = storage.load([ArchivedTaskItem].self, from: .taskArchive, fallback: [])
        let loadedHabits = storage.load([HabitItem].self, from: .habits, fallback: [])
        let loadedFocusLog = storage.load([FocusLogEntry].self, from: .focusLog, fallback: [])
        let loadedCloudSyncMetadata = storage.load(CloudSyncMetadata.self, from: .cloudSyncMeta, fallback: .empty)
        let loadedBackendTaskSyncState = storage.load(BackendTaskSyncState.self, from: .backendTaskSyncMeta, fallback: .empty)

        self.settings = loadedSettings
        self.topOrder = loadedSettings.topBarOrder
        self.cloudSyncMetadata = loadedCloudSyncMetadata
        self.cloudSyncLastSuccessfulAt = loadedCloudSyncMetadata.lastSuccessfulSyncAt
        self.backendTaskSyncState = loadedBackendTaskSyncState

        self.focusViewModel = FocusViewModel(logs: loadedFocusLog) { [storage] logs in
            storage.save(logs, to: .focusLog)
        }
        self.focusViewModel.dailyGoal = loadedSettings.dailyFocusGoal

        self.tasksViewModel = TasksViewModel(tasks: loadedTasks, archivedTasks: loadedTaskArchive) { [storage] tasks, archivedTasks in
            storage.save(tasks, to: .tasks)
            storage.save(archivedTasks, to: .taskArchive)
        }

        self.habitsViewModel = HabitsViewModel(habits: loadedHabits) { [storage] habits in
            storage.save(habits, to: .habits)
        }

        wireServices()
        applyAppearance()

        serialService.setAutoReconnect(enabled: loadedSettings.autoReconnect)
        serialService.preferredPort = loadedSettings.preferredSerialPort
        serialService.selectedPort = loadedSettings.preferredSerialPort
        if loadedSettings.autoReconnect, let preferred = loadedSettings.preferredSerialPort {
            serialService.connect(to: preferred)
        }

        gamificationService.recomputeFocusStreak(
            from: focusViewModel.logs,
            dailyGoal: loadedSettings.dailyFocusGoal
        )

        serialService.sendView(screen: route.rawValue)
        sendGamifySnapshotToESP(reason: "init")
        startClockSync()
        startStatsSync()
        startDailyLoop()
        configureStatisticsAutoExportTimer()
        registerAppWillTerminateObserver()
        captureStatisticsSnapshot()
        configureCloudSyncPolling()
        scheduleCloudSync(reason: "app launch", immediate: true)
    }

    deinit {
        if let appWillTerminateObserver {
            NotificationCenter.default.removeObserver(appWillTerminateObserver)
        }
        cloudSyncPollingTimer?.cancel()
        statisticsAutoExportTimer?.cancel()
        dailyLoopTimer?.cancel()
        cloudSyncDebounceTask?.cancel()
    }

    func navigate(to route: AppRoute) {
        withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
            self.route = route
        }
    }

    func persistTopOrder(_ order: [AppRoute]) {
        let normalized = Self.normalizedTopOrder(order)
        topOrder = normalized
        settings.topBarOrder = normalized
    }

    func toggleWidget(_ widget: HomeWidgetKind, enabled: Bool) {
        if enabled {
            if settings.homeWidgets.contains(widget) == false {
                settings.homeWidgets.append(widget)
            }
        } else {
            settings.homeWidgets.removeAll { $0 == widget }
        }
    }

    // =====================================================
    // MARK: - Statistics Export API
    // [TAG: V2_STATS_EXPORT_API]
    // =====================================================

    @discardableResult
    func exportStatisticsNow() async -> Bool {
        let snapshot = buildStatisticsSnapshot()
        await statisticsExportService.ingest(snapshot: snapshot)

        do {
            _ = try await statisticsExportService.exportWorkbooks()
            statisticsLastExportDate = Date()
            statisticsLastExportError = nil
            return true
        } catch {
            statisticsLastExportError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func openStatisticsWorkbook() async -> Bool {
        do {
            let url = try await statisticsExportService.statsWorkbookURL()
            return NSWorkspace.shared.open(url)
        } catch {
            statisticsLastExportError = error.localizedDescription
            return false
        }
    }

    var cloudSyncStatusIcon: String {
        switch cloudSyncStatus {
        case .checking:
            return "folder.badge.questionmark"
        case .active:
            return "folder.badge.checkmark"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .disabled:
            return "folder.badge.minus"
        case .unavailable:
            return "folder.badge.exclamationmark"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    var cloudSyncStatusTitle: String {
        switch cloudSyncStatus {
        case .checking:
            return "Checking Sync…"
        case .active:
            return "Sync Active"
        case .syncing:
            return "Syncing…"
        case .disabled:
            return "Sync Disabled"
        case .unavailable:
            return "Folder Unavailable"
        case .error:
            return "Sync Error"
        }
    }

    var cloudSyncStatusDetail: String {
        switch cloudSyncStatus {
        case .checking:
            return "Verifying sync channels."
        case .active:
            return "Changes sync in the background while local data stays available offline."
        case .syncing:
            return "Uploading and merging local changes."
        case .disabled:
            return "Local-only mode is active."
        case .unavailable(let reason):
            return reason
        case .error(let message):
            return message
        }
    }

    @discardableResult
    func syncWithICloudNow() async -> Bool {
        await runCloudSync(reason: "manual")
    }

    var syncFolderDisplayPath: String {
        if let configured = settings.syncFolderPath, configured.isEmpty == false {
            return configured
        }
        return "No folder selected"
    }

    var hasConfiguredSyncFolder: Bool {
        settings.syncFolderPath?.isEmpty == false
    }

    func pickSyncFolder() {
        let panel = NSOpenPanel()
        panel.prompt = "Select"
        panel.message = "Choose a folder in iCloud Drive for Maddy sync files."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = Self.defaultICloudDriveBaseFolder()

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.syncFolderPath = url.path
        scheduleCloudSync(reason: "sync folder selected", immediate: true)
    }

    func clearSyncFolder() {
        settings.syncFolderPath = nil
    }

    func openSyncFolderInFinder() {
        guard let folderURL = resolvedSyncFolderURL(createIfMissing: true) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }

    // =====================================================
    // MARK: - Calendar Subscriptions
    // [TAG: V2_CALENDAR_SUBSCRIPTIONS]
    // =====================================================

    @discardableResult
    func addICalSubscription(urlString: String, name: String? = nil) -> Bool {
        let normalized = Self.normalizedICalURL(urlString)
        guard normalized.isEmpty == false, URL(string: normalized) != nil else {
            return false
        }

        if settings.iCalSubscriptions.contains(where: { $0.urlString.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return false
        }

        let displayName: String
        if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let host = URL(string: normalized)?.host, host.isEmpty == false {
            displayName = host
        } else {
            displayName = "Subscribed Calendar"
        }

        settings.iCalSubscriptions.append(
            ICalSubscription(
                id: UUID(),
                name: displayName,
                urlString: normalized,
                isEnabled: true,
                lastRefreshAt: nil,
                lastError: nil
            )
        )
        return true
    }

    func removeICalSubscription(id: UUID) {
        settings.iCalSubscriptions.removeAll { $0.id == id }
    }

    func updateICalSubscriptionEnabled(id: UUID, isEnabled: Bool) {
        guard let index = settings.iCalSubscriptions.firstIndex(where: { $0.id == id }) else { return }
        settings.iCalSubscriptions[index].isEnabled = isEnabled
    }

    func updateICalSubscriptionRefreshMetadata(id: UUID, refreshedAt: Date?, error: String?) {
        guard let index = settings.iCalSubscriptions.firstIndex(where: { $0.id == id }) else { return }
        settings.iCalSubscriptions[index].lastRefreshAt = refreshedAt ?? settings.iCalSubscriptions[index].lastRefreshAt
        settings.iCalSubscriptions[index].lastError = error
    }

    private func wireServices() {
        aiService.gamificationContextProvider = { [weak self] in
            guard let self else { return "(none)" }
            return "Level \(self.gamificationService.currentLevel), totalXP \(self.gamificationService.totalXP), focusStreak \(self.gamificationService.dailyFocusStreak)."
        }

        aiService.onXPReward = { [weak self] amount, reason in
            self?.gamificationService.awardBonusXP(amount, reason: reason)
        }

        focusViewModel.onTick = { [weak self] phase, remaining, total, running in
            self?.serialService.sendPomodoro(
                phase: phase.espIdentifier,
                remaining: remaining,
                total: total,
                running: running
            )
        }
        focusViewModel.onSessionCompleted = { [weak self] entry in
            guard let self else { return }
            self.gamificationService.registerFocusSession(
                entry,
                dailyGoal: self.settings.dailyFocusGoal,
                allLogs: self.focusViewModel.logs
            )
        }

        tasksViewModel.onStartFocus = { [weak self] task in
            self?.navigate(to: .focus)
            self?.focusViewModel.startFromTask(task.title)
        }
        tasksViewModel.onTaskCompleted = { [weak self] task in
            guard let self else { return }
            let completedToday = self.tasksViewModel.completedNormalTasksCount(for: Date())
            self.gamificationService.registerTaskCompletion(task, completedToday: completedToday)
        }
        tasksViewModel.onDailyTaskMissed = { [weak self] task in
            self?.gamificationService.registerMissedDailyTask(task)
        }
        habitsViewModel.onHabitCompleted = { [weak self] habit in
            guard let self else { return }
            let lower = habit.title.lowercased()
            let required = lower.contains("required") || lower.contains("must")
            self.gamificationService.registerHabitCompletion(habit, isRequired: required)
        }

        serialService.$isConnected
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                guard let self else { return }
                guard connected else { return }
                self.serialService.sendView(screen: self.route.rawValue)
                self.sendGamifySnapshotToESP(reason: "serial connected")
                self.sendAIStyleSnapshotToESP(reason: "serial connected")
            }
            .store(in: &cancellables)

        serialService.$helloScreen
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.sendGamifySnapshotToESP(reason: "serial hello")
                self?.sendAIStyleSnapshotToESP(reason: "serial hello")
            }
            .store(in: &cancellables)

        serialService.$debugLines
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.route != .settings, self.settings.debugLogsEnabled {
                    self.showMenuBarHint = true
                }
            }
            .store(in: &cancellables)

        focusViewModel.$logs
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.captureStatisticsSnapshot()
                guard self.isApplyingCloudSnapshot == false else { return }
                self.markDomainChanged(.focus)
                self.scheduleCloudSync(reason: "focus logs changed")
            }
            .store(in: &cancellables)

        habitsViewModel.$habits
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.captureStatisticsSnapshot()
                guard self.isApplyingCloudSnapshot == false else { return }
                self.markDomainChanged(.habits)
                self.scheduleCloudSync(reason: "habits changed")
            }
            .store(in: &cancellables)

        tasksViewModel.$tasks
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.captureStatisticsSnapshot()
                guard self.isApplyingCloudSnapshot == false else { return }
                self.markDomainChanged(.tasks)
                self.scheduleCloudSync(reason: "tasks changed")
            }
            .store(in: &cancellables)

        tasksViewModel.$archivedTasks
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.captureStatisticsSnapshot()
                guard self.isApplyingCloudSnapshot == false else { return }
                self.markDomainChanged(.tasks)
                self.scheduleCloudSync(reason: "task archive changed")
            }
            .store(in: &cancellables)

        gamificationService.$totalXP
            .dropFirst()
            .sink { [weak self] _ in
                self?.captureStatisticsSnapshot()
            }
            .store(in: &cancellables)

        gamificationService.$skills
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sendGamifySnapshotToESP(reason: "skills changed")
                guard self.isApplyingCloudSnapshot == false else { return }
                self.markDomainChanged(.gamification)
                self.scheduleCloudSync(reason: "gamification skills changed")
            }
            .store(in: &cancellables)

        gamificationService.$totalXP
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.sendGamifySnapshotToESP(reason: "xp changed")
                guard self.isApplyingCloudSnapshot == false else { return }
                self.markDomainChanged(.gamification)
                self.scheduleCloudSync(reason: "gamification xp changed")
            }
            .store(in: &cancellables)
    }

    private func persistSettings() {
        storage.save(settings, to: .settings)
    }

    private func applyAppearance() {
        DispatchQueue.main.async {
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func startClockSync() {
        serialService.sendCurrentTime()
        clockTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.serialService.sendCurrentTime()
            }
    }

    private func startStatsSync() {
        sendDailyFocusStatsToESP()
        statsTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendDailyFocusStatsToESP()
            }
    }

    private func startDailyLoop() {
        runDailyLoopTick()
        dailyLoopTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.runDailyLoopTick()
            }
    }

    private func sendDailyFocusStatsToESP() {
        guard serialService.isConnected else { return }
        serialService.sendLine("stats:daily=\(focusViewModel.todayFocusMinutes)")
    }

    private func runDailyLoopTick() {
        tasksViewModel.applyDailyRollover()
        let smartTemplates = gamificationService.generateSmartDailyTaskTemplates()
        tasksViewModel.ensureDailyTaskCapacity(
            count: settings.dailyTaskCount,
            templates: smartTemplates
        )

        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        guard hour == 20, minute <= 2 else { return }

        let requiredHabits = habitsViewModel.habits.filter {
            let lower = $0.title.lowercased()
            return lower.contains("required") || lower.contains("must")
        }
        let dayKey = now.yyyymmdd
        let completedRequired = requiredHabits.filter {
            $0.history[dayKey, default: 0] >= $0.targetPerDay
        }.count

        let evaluation = GamificationDayEvaluation(
            date: now,
            dailyTasks: tasksViewModel.dailyTasks(for: now) + tasksViewModel.completedDailyTasks(for: now),
            requiredHabitCount: requiredHabits.count,
            completedRequiredHabitCount: completedRequired,
            focusGoalReached: focusViewModel.todaySessions >= max(1, settings.dailyFocusGoal),
            completedNormalTaskCount: tasksViewModel.completedNormalTasksCount(for: now)
        )
        gamificationService.evaluateDay(evaluation)
    }

    private func sendGamifySnapshotToESP(reason: String) {
        guard serialService.isConnected else { return }
        _ = reason

        let axes = GamificationSkillAxis.allCases
        var values: [Int] = axes.map { axis in
            let normalized = gamificationService.skills[axis]?.normalized0to1 ?? 0.0
            let clamped = min(1.0, max(0.0, normalized))
            return Int((clamped * 100.0).rounded())
        }

        values.append(gamificationService.momentum)
        values.append(gamificationService.reliabilityNormalized)
        if values.count > 6 {
            values = Array(values.prefix(6))
        }
        while values.count < 6 {
            values.append(0)
        }

        serialService.sendGamify(level: gamificationService.currentLevel, values: values)
    }

    private func sendAIStyleSnapshotToESP(reason: String) {
        guard serialService.isConnected else { return }
        _ = reason
        serialService.sendAIStyle(settings.aiPlaceholderStyle.rawValue)
    }

    // =====================================================
    // MARK: - iCloud Sync
    // [TAG: V2_ICLOUD_SYNC]
    // =====================================================

    private var isAnySyncEnabled: Bool {
        settings.iCloudSyncEnabled || settings.backendSyncEnabled
    }

    private func configureCloudSyncPolling() {
        cloudSyncPollingTimer?.cancel()
        guard isAnySyncEnabled else { return }

        cloudSyncPollingTimer = Timer.publish(every: 45, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.scheduleCloudSync(reason: "periodic refresh", immediate: true)
            }
    }

    private func scheduleCloudSync(reason: String, immediate: Bool = false) {
        guard isAnySyncEnabled else {
            cloudSyncStatus = .disabled
            return
        }

        cloudSyncDebounceTask?.cancel()
        let delayNanos: UInt64 = immediate ? 0 : 1_000_000_000

        cloudSyncDebounceTask = Task { [weak self] in
            guard let self else { return }
            if delayNanos > 0 {
                try? await Task.sleep(nanoseconds: delayNanos)
            }
            guard Task.isCancelled == false else { return }
            _ = await self.runCloudSync(reason: reason)
        }
    }

    private func markDomainChanged(_ domain: CloudSyncDomain, at date: Date = Date()) {
        cloudSyncMetadata.modifiedAt[domain.rawValue] = date
        persistCloudSyncMetadata()
    }

    private func modifiedDate(for domain: CloudSyncDomain) -> Date {
        cloudSyncMetadata.modifiedAt[domain.rawValue] ?? .distantPast
    }

    private func persistCloudSyncMetadata() {
        storage.save(cloudSyncMetadata, to: .cloudSyncMeta)
        cloudSyncLastSuccessfulAt = cloudSyncMetadata.lastSuccessfulSyncAt
    }

    private func persistBackendTaskSyncState() {
        storage.save(backendTaskSyncState, to: .backendTaskSyncMeta)
    }

    @discardableResult
    private func runCloudSync(reason: String) async -> Bool {
        _ = reason
        guard isAnySyncEnabled else {
            cloudSyncStatus = .disabled
            return false
        }
        guard cloudSyncInFlight == false else { return false }

        cloudSyncInFlight = true
        cloudSyncStatus = .syncing
        defer { cloudSyncInFlight = false }

        var succeeded = false
        var failures: [String] = []

        if settings.backendSyncEnabled {
            let backendSucceeded = await runBackendTaskSync()
            succeeded = succeeded || backendSucceeded
            if backendSucceeded == false {
                failures.append("Backend sync failed")
            }
        }

        if settings.iCloudSyncEnabled {
            let folderResult = await runFolderSync()
            succeeded = succeeded || folderResult
            if folderResult == false {
                failures.append("Folder sync failed")
            }
        }

        if succeeded {
            cloudSyncMetadata.lastSuccessfulSyncAt = Date()
            persistCloudSyncMetadata()
            cloudSyncStatus = .active
            return true
        }

        cloudSyncStatus = .error(failures.first ?? "Sync failed")
        return false
    }

    @discardableResult
    private func runFolderSync() async -> Bool {
        do {
            let allDomains = CloudSyncDomain.allCases
            guard let folderURL = resolvedSyncFolderURL(createIfMissing: true) else {
                if settings.backendSyncEnabled {
                    return false
                }
                cloudSyncStatus = .unavailable("Select an iCloud Drive folder in Settings to enable sync.")
                return false
            }

            var remoteRecords: [CloudSyncDomain: CloudSyncEnvelope] = [:]
            for domain in allDomains {
                let fileURL = folderURL.appendingPathComponent(domain.fileName)
                if let envelope = try loadCloudSyncEnvelope(from: fileURL) {
                    remoteRecords[domain] = envelope
                    continue
                }

                for legacyName in domain.legacyFileNames {
                    let legacyURL = folderURL.appendingPathComponent(legacyName)
                    if let legacyEnvelope = try loadCloudSyncEnvelope(from: legacyURL) {
                        remoteRecords[domain] = legacyEnvelope
                        break
                    }
                }
            }

            var appliedAnyRemote = false
            isApplyingCloudSnapshot = true
            defer { isApplyingCloudSnapshot = false }

            for domain in allDomains {
                guard let remote = remoteRecords[domain] else { continue }
                guard remote.modifiedAt > modifiedDate(for: domain) else { continue }

                let applied = applyRemotePayload(remote.payloadData, for: domain)
                if applied {
                    markDomainChanged(domain, at: remote.modifiedAt)
                    appliedAnyRemote = true
                }
            }

            var pushedAnyLocal = false
            for domain in allDomains {
                let localDate = modifiedDate(for: domain)
                let remoteDate = remoteRecords[domain]?.modifiedAt ?? .distantPast
                guard localDate > remoteDate || remoteRecords[domain] == nil else { continue }
                guard let payload = encodedCloudPayload(for: domain) else { continue }

                let effectiveDate = localDate == .distantPast ? Date() : localDate
                let fileURL = folderURL.appendingPathComponent(domain.fileName)
                try saveCloudSyncEnvelope(
                    CloudSyncEnvelope(modifiedAt: effectiveDate, payloadData: payload),
                    to: fileURL
                )
                markDomainChanged(domain, at: effectiveDate)
                pushedAnyLocal = true
            }

            if appliedAnyRemote || pushedAnyLocal {
                cloudSyncMetadata.lastSuccessfulSyncAt = Date()
                persistCloudSyncMetadata()
            }

            return true
        } catch {
            return false
        }
    }

    @discardableResult
    private func runBackendTaskSync() async -> Bool {
        do {
            let baseURL = try normalizedBackendBaseURL(from: settings.backendBaseURL)
            let headers = backendHeaders(clientDeviceID: settings.backendClientDeviceID)

            var cursor = backendTaskSyncState.cursor
            var changed = false
            var hasMore = true
            var safetyCounter = 0

            while hasMore, safetyCounter < 20 {
                safetyCounter += 1
                let pullPath = "sync/pull?cursor=\(cursor)&limit=200"
                let pull = try await performBackendRequest(
                    baseURL: baseURL,
                    path: pullPath,
                    method: "GET",
                    headers: headers,
                    requestBody: Optional<EmptyBody>.none,
                    responseType: BackendPullResponse.self
                )

                if pull.changes.isEmpty == false {
                    changed = true
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
                requestBody: BackendAckRequest(clientDeviceId: settings.backendClientDeviceID, cursor: cursor),
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
                    let requestBody = BackendPushRequest(clientDeviceId: settings.backendClientDeviceID, mutations: chunk)
                    _ = try await performBackendRequest(
                        baseURL: baseURL,
                        path: "sync/push",
                        method: "POST",
                        headers: headers,
                        requestBody: requestBody,
                        responseType: BackendPushResponse.self
                    )
                }
            }

            backendTaskSyncState.cursor = cursor
            let finalSignatures = currentBackendTaskPayloads().reduce(into: [String: String]()) { partial, entry in
                partial[entry.id.lowercased()] = backendTaskSignature(for: entry)
            }
            backendTaskSyncState.taskSignatures = finalSignatures
            persistBackendTaskSyncState()

            if changed {
                markDomainChanged(.tasks)
            }

            return true
        } catch {
            return false
        }
    }

    private func applyBackendTaskChanges(_ changes: [BackendChange]) {
        guard changes.isEmpty == false else { return }

        var active = tasksViewModel.tasks
        var archived = tasksViewModel.archivedTasks
        var activeByID = Dictionary(uniqueKeysWithValues: active.enumerated().map { ($0.element.id, $0.offset) })
        var archivedByTaskID = Dictionary(uniqueKeysWithValues: archived.enumerated().map { ($0.element.task.id, $0.offset) })

        for change in changes where change.entityType == "task" {
            guard let payload = change.payload, let parsed = payload.toTaskItem() else { continue }
            let id = parsed.id
            let removeTask = change.operation == "deleted" || payload.deletedAt != nil || payload.status == "deleted"

            if removeTask {
                if let index = activeByID[id] {
                    active.remove(at: index)
                    activeByID = Dictionary(uniqueKeysWithValues: active.enumerated().map { ($0.element.id, $0.offset) })
                }
                if let archiveIndex = archivedByTaskID[id] {
                    archived.remove(at: archiveIndex)
                    archivedByTaskID = Dictionary(uniqueKeysWithValues: archived.enumerated().map { ($0.element.task.id, $0.offset) })
                }
                continue
            }

            let existingNote = active.first(where: { $0.id == id })?.notes
                ?? archived.first(where: { $0.task.id == id })?.task.notes
                ?? ""
            let existingRecurrence = active.first(where: { $0.id == id })?.recurrence
                ?? archived.first(where: { $0.task.id == id })?.task.recurrence
                ?? .none
            let existingOrder = active.first(where: { $0.id == id })?.order
                ?? archived.first(where: { $0.task.id == id })?.task.order
                ?? 0

            var task = parsed
            task.notes = existingNote
            task.recurrence = existingRecurrence
            task.order = existingOrder

            if task.status == .done || task.status == .missed {
                if let index = activeByID[id] {
                    active.remove(at: index)
                    activeByID = Dictionary(uniqueKeysWithValues: active.enumerated().map { ($0.element.id, $0.offset) })
                }

                let archivedEntry = ArchivedTaskItem(
                    id: archived.first(where: { $0.task.id == id })?.id ?? UUID(),
                    task: task,
                    archivedAt: archived.first(where: { $0.task.id == id })?.archivedAt ?? Date(),
                    sourceStatus: archived.first(where: { $0.task.id == id })?.sourceStatus ?? task.status
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

        isApplyingCloudSnapshot = true
        tasksViewModel.tasks = active
        tasksViewModel.archivedTasks = archived
        storage.save(active, to: .tasks)
        storage.save(archived, to: .taskArchive)
        isApplyingCloudSnapshot = false
    }

    private func currentBackendTaskPayloads() -> [BackendTaskPayload] {
        var records: [UUID: TaskItem] = [:]
        for task in tasksViewModel.tasks {
            records[task.id] = task
        }
        for archived in tasksViewModel.archivedTasks {
            let candidate = archived.task
            if let existing = records[candidate.id] {
                if candidate.updatedAt > existing.updatedAt {
                    records[candidate.id] = candidate
                }
            } else {
                records[candidate.id] = candidate
            }
        }

        return records.values.map { BackendTaskPayload(task: $0) }
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
            if let queriedURL = components?.url {
                url = queriedURL
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

    private func encodedCloudPayload(for domain: CloudSyncDomain) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        switch domain {
        case .tasks:
            let payload = CloudTasksPayload(tasks: tasksViewModel.tasks, archivedTasks: tasksViewModel.archivedTasks)
            return try? encoder.encode(payload)
        case .habits:
            let payload = CloudHabitsPayload(habits: habitsViewModel.habits)
            return try? encoder.encode(payload)
        case .focus:
            let payload = CloudFocusPayload(logs: focusViewModel.logs)
            return try? encoder.encode(payload)
        case .gamification:
            return try? encoder.encode(gamificationService.cloudSnapshot())
        case .sharedSettings:
            let payload = CloudSharedSettingsPayload(snapshot: settings.sharedSettingsSnapshot())
            return try? encoder.encode(payload)
        case .macPlatformSettings:
            let payload = CloudSettingsPayload(snapshot: settings.cloudSnapshot())
            return try? encoder.encode(payload)
        case .calendarSources:
            let payload = CloudCalendarSourcesPayload(
                iCalSubscriptions: settings.iCalSubscriptions,
                showGoogleCalendarEvents: settings.showGoogleCalendarEvents,
                showICalCalendarEvents: settings.showICalCalendarEvents,
                showTaskCalendarEntries: settings.showTaskCalendarEntries
            )
            return try? encoder.encode(payload)
        }
    }

    private func applyRemotePayload(_ payload: Data, for domain: CloudSyncDomain) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        switch domain {
        case .tasks:
            guard let decoded = try? decoder.decode(CloudTasksPayload.self, from: payload) else { return false }
            tasksViewModel.tasks = decoded.tasks
            tasksViewModel.archivedTasks = decoded.archivedTasks
            storage.save(decoded.tasks, to: .tasks)
            storage.save(decoded.archivedTasks, to: .taskArchive)
            return true
        case .habits:
            guard let decoded = try? decoder.decode(CloudHabitsPayload.self, from: payload) else { return false }
            habitsViewModel.habits = decoded.habits
            storage.save(decoded.habits, to: .habits)
            return true
        case .focus:
            guard let decoded = try? decoder.decode(CloudFocusPayload.self, from: payload) else { return false }
            focusViewModel.logs = decoded.logs
            storage.save(decoded.logs, to: .focusLog)
            gamificationService.recomputeFocusStreak(
                from: decoded.logs,
                dailyGoal: settings.dailyFocusGoal
            )
            return true
        case .gamification:
            if let decoded = try? decoder.decode(GamificationService.CloudSnapshot.self, from: payload) {
                gamificationService.applyCloudSnapshot(decoded)
                return true
            }
            if let wrapped = try? decoder.decode(CloudGamificationPayload.self, from: payload) {
                gamificationService.applyCloudSnapshot(wrapped.snapshot)
                return true
            }
            return false
        case .sharedSettings:
            var merged = settings
            if let decoded = try? decoder.decode(CloudSharedSettingsPayload.self, from: payload) {
                merged.applySharedSettingsSnapshot(decoded.snapshot)
            } else if let legacyMac = try? decoder.decode(CloudSettingsPayload.self, from: payload) {
                merged.applySharedSettingsSnapshot(
                    MaddySettings.SharedSettingsSnapshot(
                        accentHex: legacyMac.snapshot.accentHex,
                        focusSoundEnabled: legacyMac.snapshot.focusSoundEnabled,
                        dailyTaskCount: legacyMac.snapshot.dailyTaskCount,
                        dailySummaryEnabled: legacyMac.snapshot.dailySummaryEnabled
                    )
                )
            } else if let legacyMobile = try? decoder.decode(CloudLegacyMobileSettingsSnapshot.self, from: payload) {
                merged.applySharedSettingsSnapshot(
                    MaddySettings.SharedSettingsSnapshot(
                        accentHex: legacyMobile.accentHex,
                        focusSoundEnabled: legacyMobile.soundEnabled,
                        dailyTaskCount: max(1, legacyMobile.dailyTaskCount ?? merged.dailyTaskCount),
                        dailySummaryEnabled: legacyMobile.dailySummaryEnabled ?? merged.dailySummaryEnabled
                    )
                )
            } else {
                return false
            }
            settings = merged
            return true
        case .macPlatformSettings:
            guard let decoded = try? decoder.decode(CloudSettingsPayload.self, from: payload) else { return false }
            var merged = settings
            merged.applyCloudSnapshot(decoded.snapshot)
            settings = merged
            return true
        case .calendarSources:
            guard let decoded = try? decoder.decode(CloudCalendarSourcesPayload.self, from: payload) else { return false }
            var merged = settings
            merged.iCalSubscriptions = decoded.iCalSubscriptions
            merged.showGoogleCalendarEvents = decoded.showGoogleCalendarEvents
            merged.showICalCalendarEvents = decoded.showICalCalendarEvents
            merged.showTaskCalendarEntries = decoded.showTaskCalendarEntries
            settings = merged
            return true
        }
    }

    private func resolvedSyncFolderURL(createIfMissing: Bool) -> URL? {
        guard let path = settings.syncFolderPath, path.isEmpty == false else { return nil }
        let folderURL = URL(fileURLWithPath: path, isDirectory: true)

        if createIfMissing {
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return folderURL
    }

    private static func defaultICloudDriveBaseFolder() -> URL? {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return base
    }

    private static func defaultCloudSyncFolderURL(createIfMissing: Bool) -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []

        if let iCloudBase = defaultICloudDriveBaseFolder() {
            candidates.append(iCloudBase.appendingPathComponent("ESP-Projects/MaddySuite/Icloud-Sync", isDirectory: true))
            candidates.append(iCloudBase.appendingPathComponent("MaddySuite/Icloud-Sync", isDirectory: true))
        }

        let cwdCandidate = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Icloud-Sync", isDirectory: true)
        candidates.append(cwdCandidate)

        for candidate in candidates {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }

        guard createIfMissing, let preferred = candidates.first else { return nil }
        do {
            try fm.createDirectory(at: preferred, withIntermediateDirectories: true)
            return preferred
        } catch {
            return nil
        }
    }

    private static func bootstrapCloudSyncDefaults(in settings: inout MaddySettings) {
        if (settings.syncFolderPath?.isEmpty ?? true),
           let defaultFolder = defaultCloudSyncFolderURL(createIfMissing: true) {
            settings.syncFolderPath = defaultFolder.path
        }

        if settings.syncFolderPath?.isEmpty == false,
           settings.iCloudSyncEnabled == false,
           settings.backendSyncEnabled == false {
            settings.iCloudSyncEnabled = true
        }
    }

    private func loadCloudSyncEnvelope(from url: URL) throws -> CloudSyncEnvelope? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CloudSyncEnvelope.self, from: data)
    }

    private func saveCloudSyncEnvelope(_ envelope: CloudSyncEnvelope, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        try data.write(to: url, options: .atomic)
    }

    private static func syncErrorMessage(for error: Error) -> String {
        "Folder sync failed: \(error.localizedDescription)"
    }

    // =====================================================
    // MARK: - Statistics Export Internals
    // [TAG: V2_STATS_EXPORT_INTERNAL]
    // =====================================================

    private func configureStatisticsAutoExportTimer() {
        statisticsAutoExportTimer?.cancel()

        guard settings.autoExportStatistics else { return }

        statisticsAutoExportTimer = Timer.publish(every: 3600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { [weak self] in
                    guard let self else { return }
                    _ = await self.exportStatisticsNow()
                }
            }
    }

    private func registerAppWillTerminateObserver() {
        appWillTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                _ = await self.exportStatisticsNow()
                _ = await self.runCloudSync(reason: "app terminate")
            }
        }
    }

    private func captureStatisticsSnapshot() {
        let snapshot = buildStatisticsSnapshot()
        Task {
            await statisticsExportService.ingest(snapshot: snapshot)
        }
    }

    private func buildStatisticsSnapshot() -> StatisticsSnapshot {
        let focusEntries = focusViewModel.logs.map { log in
            StatisticsSnapshot.FocusEntry(
                id: log.id.uuidString,
                startedAt: log.startedAt,
                durationSeconds: log.durationSeconds
            )
        }

        let habitEntries: [StatisticsSnapshot.HabitEntry] = habitsViewModel.habits.flatMap { habit in
            habit.history.map { key, value in
                StatisticsSnapshot.HabitEntry(
                    habitID: habit.id.uuidString,
                    habitName: habit.title,
                    dateKey: key,
                    value: value,
                    target: max(1, habit.targetPerDay)
                )
            }
        }

        let activeTaskEntries = tasksViewModel.tasks.map { task in
            StatisticsSnapshot.TaskEntry(
                id: task.id.uuidString,
                title: task.title,
                status: task.status.rawValue,
                dueDate: task.dueDate,
                doneDate: task.completedAt
            )
        }

        let archivedTaskEntries = tasksViewModel.archivedTasks.map { archived in
            StatisticsSnapshot.TaskEntry(
                id: archived.task.id.uuidString,
                title: archived.task.title,
                status: archived.task.status.rawValue,
                dueDate: archived.task.dueDate,
                doneDate: archived.task.completedAt
            )
        }

        return StatisticsSnapshot(
            focusEntries: focusEntries,
            habitEntries: habitEntries,
            taskEntries: activeTaskEntries + archivedTaskEntries,
            totalXP: gamificationService.totalXP,
            level: gamificationService.currentLevel,
            capturedAt: Date()
        )
    }

    private static func normalizedICalURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }
        if trimmed.lowercased().hasPrefix("webcal://") {
            return "https://" + trimmed.dropFirst("webcal://".count)
        }
        return trimmed
    }

    nonisolated private static func normalizedTopOrder(_ order: [AppRoute]) -> [AppRoute] {
        var normalized = order
        for route in AppRoute.allCases where normalized.contains(route) == false {
            normalized.append(route)
        }
        return normalized
    }
}

// =====================================================
// MARK: - Settings
// [TAG: V2_SETTINGS_MODEL]
// =====================================================

struct MaddySettings: Codable {
    var accentHex: String
    var glassIntensity: Double
    var topBarOrder: [AppRoute]
    var homeWidgets: [HomeWidgetKind]

    var preferredSerialPort: String?
    var autoReconnect: Bool
    var debugLogsEnabled: Bool

    var menuBarEnabled: Bool

    var focusSoundEnabled: Bool
    var focusSoundVolume: Double
    var dailyFocusGoal: Int
    var dailyTaskCount: Int
    var dailySummaryEnabled: Bool

    var taskDefaultPriority: TaskPriority
    var habitWeekStartsMonday: Bool
    var autoExportStatistics: Bool
    var aiPlaceholderStyle: AIPlaceholderStyle
    var showGoogleCalendarEvents: Bool
    var showICalCalendarEvents: Bool
    var showTaskCalendarEntries: Bool
    var iCalSubscriptions: [ICalSubscription]
    var iCloudSyncEnabled: Bool
    var syncFolderPath: String?
    var backendSyncEnabled: Bool
    var backendBaseURL: String
    var backendClientDeviceID: String

    enum CodingKeys: String, CodingKey {
        case accentHex
        case glassIntensity
        case topBarOrder
        case homeWidgets
        case preferredSerialPort
        case autoReconnect
        case debugLogsEnabled
        case menuBarEnabled
        case focusSoundEnabled
        case focusSoundVolume
        case dailyFocusGoal
        case dailyTaskCount
        case dailySummaryEnabled
        case taskDefaultPriority
        case habitWeekStartsMonday
        case autoExportStatistics
        case aiPlaceholderStyle
        case showGoogleCalendarEvents
        case showICalCalendarEvents
        case showTaskCalendarEntries
        case iCalSubscriptions
        case iCloudSyncEnabled
        case syncFolderPath
        case backendSyncEnabled
        case backendBaseURL
        case backendClientDeviceID
    }

    nonisolated private static func normalizedTopOrder(_ order: [AppRoute]) -> [AppRoute] {
        var normalized = order
        for route in AppRoute.allCases where normalized.contains(route) == false {
            normalized.append(route)
        }
        return normalized
    }

    init(
        accentHex: String,
        glassIntensity: Double,
        topBarOrder: [AppRoute],
        homeWidgets: [HomeWidgetKind],
        preferredSerialPort: String?,
        autoReconnect: Bool,
        debugLogsEnabled: Bool,
        menuBarEnabled: Bool,
        focusSoundEnabled: Bool,
        focusSoundVolume: Double,
        dailyFocusGoal: Int,
        dailyTaskCount: Int,
        dailySummaryEnabled: Bool,
        taskDefaultPriority: TaskPriority,
        habitWeekStartsMonday: Bool,
        autoExportStatistics: Bool,
        aiPlaceholderStyle: AIPlaceholderStyle,
        showGoogleCalendarEvents: Bool,
        showICalCalendarEvents: Bool,
        showTaskCalendarEntries: Bool,
        iCalSubscriptions: [ICalSubscription],
        iCloudSyncEnabled: Bool,
        syncFolderPath: String?,
        backendSyncEnabled: Bool,
        backendBaseURL: String,
        backendClientDeviceID: String
    ) {
        self.accentHex = accentHex
        self.glassIntensity = glassIntensity
        self.topBarOrder = topBarOrder
        self.homeWidgets = homeWidgets
        self.preferredSerialPort = preferredSerialPort
        self.autoReconnect = autoReconnect
        self.debugLogsEnabled = debugLogsEnabled
        self.menuBarEnabled = menuBarEnabled
        self.focusSoundEnabled = focusSoundEnabled
        self.focusSoundVolume = focusSoundVolume
        self.dailyFocusGoal = dailyFocusGoal
        self.dailyTaskCount = dailyTaskCount
        self.dailySummaryEnabled = dailySummaryEnabled
        self.taskDefaultPriority = taskDefaultPriority
        self.habitWeekStartsMonday = habitWeekStartsMonday
        self.autoExportStatistics = autoExportStatistics
        self.aiPlaceholderStyle = aiPlaceholderStyle
        self.showGoogleCalendarEvents = showGoogleCalendarEvents
        self.showICalCalendarEvents = showICalCalendarEvents
        self.showTaskCalendarEntries = showTaskCalendarEntries
        self.iCalSubscriptions = iCalSubscriptions
        self.iCloudSyncEnabled = iCloudSyncEnabled
        self.syncFolderPath = syncFolderPath
        self.backendSyncEnabled = backendSyncEnabled
        self.backendBaseURL = backendBaseURL
        self.backendClientDeviceID = backendClientDeviceID
    }

    static let `default` = MaddySettings(
        accentHex: "#FF7A2F",
        glassIntensity: 0.38,
        topBarOrder: AppRoute.allCases,
        homeWidgets: HomeWidgetKind.allCases,
        preferredSerialPort: nil,
        autoReconnect: true,
        debugLogsEnabled: true,
        menuBarEnabled: true,
        focusSoundEnabled: true,
        focusSoundVolume: 0.65,
        dailyFocusGoal: 8,
        dailyTaskCount: 3,
        dailySummaryEnabled: true,
        taskDefaultPriority: .medium,
        habitWeekStartsMonday: true,
        autoExportStatistics: true,
        aiPlaceholderStyle: .orb,
        showGoogleCalendarEvents: true,
        showICalCalendarEvents: true,
        showTaskCalendarEntries: true,
        iCalSubscriptions: [],
        iCloudSyncEnabled: true,
        syncFolderPath: nil,
        backendSyncEnabled: false,
        backendBaseURL: "http://127.0.0.1:4000/v1",
        backendClientDeviceID: "mac-\(UUID().uuidString.lowercased())"
    )

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MaddySettings.default

        accentHex = try c.decodeIfPresent(String.self, forKey: .accentHex) ?? defaults.accentHex
        glassIntensity = try c.decodeIfPresent(Double.self, forKey: .glassIntensity) ?? defaults.glassIntensity
        let decodedTopOrder: [AppRoute]? = (try? c.decode([String].self, forKey: .topBarOrder))?
            .compactMap(AppRoute.init(rawValue:))
        if let decodedTopOrder, decodedTopOrder.isEmpty == false {
            topBarOrder = Self.normalizedTopOrder(decodedTopOrder)
        } else {
            topBarOrder = (try c.decodeIfPresent([AppRoute].self, forKey: .topBarOrder).map(Self.normalizedTopOrder) ?? defaults.topBarOrder)
        }

        let decodedWidgets: [HomeWidgetKind]? = (try? c.decode([String].self, forKey: .homeWidgets))?
            .compactMap(HomeWidgetKind.init(rawValue:))
        homeWidgets = decodedWidgets?.isEmpty == false
            ? decodedWidgets!
            : (try c.decodeIfPresent([HomeWidgetKind].self, forKey: .homeWidgets) ?? defaults.homeWidgets)
        preferredSerialPort = try c.decodeIfPresent(String.self, forKey: .preferredSerialPort)
        autoReconnect = try c.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? defaults.autoReconnect
        debugLogsEnabled = try c.decodeIfPresent(Bool.self, forKey: .debugLogsEnabled) ?? defaults.debugLogsEnabled
        menuBarEnabled = try c.decodeIfPresent(Bool.self, forKey: .menuBarEnabled) ?? defaults.menuBarEnabled
        focusSoundEnabled = try c.decodeIfPresent(Bool.self, forKey: .focusSoundEnabled) ?? defaults.focusSoundEnabled
        focusSoundVolume = try c.decodeIfPresent(Double.self, forKey: .focusSoundVolume) ?? defaults.focusSoundVolume
        dailyFocusGoal = try c.decodeIfPresent(Int.self, forKey: .dailyFocusGoal) ?? defaults.dailyFocusGoal
        dailyTaskCount = try c.decodeIfPresent(Int.self, forKey: .dailyTaskCount) ?? defaults.dailyTaskCount
        dailySummaryEnabled = try c.decodeIfPresent(Bool.self, forKey: .dailySummaryEnabled) ?? defaults.dailySummaryEnabled
        taskDefaultPriority = try c.decodeIfPresent(TaskPriority.self, forKey: .taskDefaultPriority) ?? defaults.taskDefaultPriority
        habitWeekStartsMonday = try c.decodeIfPresent(Bool.self, forKey: .habitWeekStartsMonday) ?? defaults.habitWeekStartsMonday
        autoExportStatistics = try c.decodeIfPresent(Bool.self, forKey: .autoExportStatistics) ?? defaults.autoExportStatistics
        aiPlaceholderStyle = try c.decodeIfPresent(AIPlaceholderStyle.self, forKey: .aiPlaceholderStyle) ?? defaults.aiPlaceholderStyle
        showGoogleCalendarEvents = try c.decodeIfPresent(Bool.self, forKey: .showGoogleCalendarEvents) ?? defaults.showGoogleCalendarEvents
        showICalCalendarEvents = try c.decodeIfPresent(Bool.self, forKey: .showICalCalendarEvents) ?? defaults.showICalCalendarEvents
        showTaskCalendarEntries = try c.decodeIfPresent(Bool.self, forKey: .showTaskCalendarEntries) ?? defaults.showTaskCalendarEntries
        iCalSubscriptions = try c.decodeIfPresent([ICalSubscription].self, forKey: .iCalSubscriptions) ?? defaults.iCalSubscriptions
        iCloudSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .iCloudSyncEnabled) ?? defaults.iCloudSyncEnabled
        syncFolderPath = try c.decodeIfPresent(String.self, forKey: .syncFolderPath)
        backendSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .backendSyncEnabled) ?? defaults.backendSyncEnabled
        backendBaseURL = try c.decodeIfPresent(String.self, forKey: .backendBaseURL) ?? defaults.backendBaseURL
        backendClientDeviceID = try c.decodeIfPresent(String.self, forKey: .backendClientDeviceID) ?? defaults.backendClientDeviceID
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(accentHex, forKey: .accentHex)
        try c.encode(glassIntensity, forKey: .glassIntensity)
        try c.encode(topBarOrder, forKey: .topBarOrder)
        try c.encode(homeWidgets, forKey: .homeWidgets)
        try c.encodeIfPresent(preferredSerialPort, forKey: .preferredSerialPort)
        try c.encode(autoReconnect, forKey: .autoReconnect)
        try c.encode(debugLogsEnabled, forKey: .debugLogsEnabled)
        try c.encode(menuBarEnabled, forKey: .menuBarEnabled)
        try c.encode(focusSoundEnabled, forKey: .focusSoundEnabled)
        try c.encode(focusSoundVolume, forKey: .focusSoundVolume)
        try c.encode(dailyFocusGoal, forKey: .dailyFocusGoal)
        try c.encode(dailyTaskCount, forKey: .dailyTaskCount)
        try c.encode(dailySummaryEnabled, forKey: .dailySummaryEnabled)
        try c.encode(taskDefaultPriority, forKey: .taskDefaultPriority)
        try c.encode(habitWeekStartsMonday, forKey: .habitWeekStartsMonday)
        try c.encode(autoExportStatistics, forKey: .autoExportStatistics)
        try c.encode(aiPlaceholderStyle, forKey: .aiPlaceholderStyle)
        try c.encode(showGoogleCalendarEvents, forKey: .showGoogleCalendarEvents)
        try c.encode(showICalCalendarEvents, forKey: .showICalCalendarEvents)
        try c.encode(showTaskCalendarEntries, forKey: .showTaskCalendarEntries)
        try c.encode(iCalSubscriptions, forKey: .iCalSubscriptions)
        try c.encode(iCloudSyncEnabled, forKey: .iCloudSyncEnabled)
        try c.encodeIfPresent(syncFolderPath, forKey: .syncFolderPath)
        try c.encode(backendSyncEnabled, forKey: .backendSyncEnabled)
        try c.encode(backendBaseURL, forKey: .backendBaseURL)
        try c.encode(backendClientDeviceID, forKey: .backendClientDeviceID)
    }
}

extension MaddySettings {
    struct SharedSettingsSnapshot: Codable, Equatable {
        var accentHex: String
        var focusSoundEnabled: Bool
        var dailyTaskCount: Int
        var dailySummaryEnabled: Bool
    }

    struct CloudSnapshot: Codable, Equatable {
        var accentHex: String
        var glassIntensity: Double
        var topBarOrder: [AppRoute]
        var homeWidgets: [HomeWidgetKind]
        var menuBarEnabled: Bool
        var focusSoundEnabled: Bool
        var focusSoundVolume: Double
        var dailyFocusGoal: Int
        var dailyTaskCount: Int
        var dailySummaryEnabled: Bool
        var taskDefaultPriority: TaskPriority
        var habitWeekStartsMonday: Bool
        var autoExportStatistics: Bool
        var aiPlaceholderStyle: AIPlaceholderStyle
        var backendSyncEnabled: Bool
        var backendBaseURL: String
        var backendClientDeviceID: String

        enum CodingKeys: String, CodingKey {
            case accentHex
            case glassIntensity
            case topBarOrder
            case homeWidgets
            case menuBarEnabled
            case focusSoundEnabled
            case focusSoundVolume
            case dailyFocusGoal
            case dailyTaskCount
            case dailySummaryEnabled
            case taskDefaultPriority
            case habitWeekStartsMonday
            case autoExportStatistics
            case aiPlaceholderStyle
            case backendSyncEnabled
            case backendBaseURL
            case backendClientDeviceID
        }

        init(
            accentHex: String,
            glassIntensity: Double,
            topBarOrder: [AppRoute],
            homeWidgets: [HomeWidgetKind],
            menuBarEnabled: Bool,
            focusSoundEnabled: Bool,
            focusSoundVolume: Double,
            dailyFocusGoal: Int,
            dailyTaskCount: Int,
            dailySummaryEnabled: Bool,
            taskDefaultPriority: TaskPriority,
            habitWeekStartsMonday: Bool,
            autoExportStatistics: Bool,
            aiPlaceholderStyle: AIPlaceholderStyle,
            backendSyncEnabled: Bool,
            backendBaseURL: String,
            backendClientDeviceID: String
        ) {
            self.accentHex = accentHex
            self.glassIntensity = glassIntensity
            self.topBarOrder = topBarOrder
            self.homeWidgets = homeWidgets
            self.menuBarEnabled = menuBarEnabled
            self.focusSoundEnabled = focusSoundEnabled
            self.focusSoundVolume = focusSoundVolume
            self.dailyFocusGoal = dailyFocusGoal
            self.dailyTaskCount = dailyTaskCount
            self.dailySummaryEnabled = dailySummaryEnabled
            self.taskDefaultPriority = taskDefaultPriority
            self.habitWeekStartsMonday = habitWeekStartsMonday
            self.autoExportStatistics = autoExportStatistics
            self.aiPlaceholderStyle = aiPlaceholderStyle
            self.backendSyncEnabled = backendSyncEnabled
            self.backendBaseURL = backendBaseURL
            self.backendClientDeviceID = backendClientDeviceID
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = MaddySettings.default.cloudSnapshot()

            accentHex = try c.decodeIfPresent(String.self, forKey: .accentHex) ?? defaults.accentHex
            glassIntensity = try c.decodeIfPresent(Double.self, forKey: .glassIntensity) ?? defaults.glassIntensity

            if let routeStrings = try? c.decode([String].self, forKey: .topBarOrder) {
                topBarOrder = MaddySettings.normalizedTopOrder(routeStrings.compactMap(AppRoute.init(rawValue:)))
            } else {
                topBarOrder = MaddySettings.normalizedTopOrder(try c.decodeIfPresent([AppRoute].self, forKey: .topBarOrder) ?? defaults.topBarOrder)
            }

            if let widgetStrings = try? c.decode([String].self, forKey: .homeWidgets) {
                let decoded = widgetStrings.compactMap(HomeWidgetKind.init(rawValue:))
                homeWidgets = decoded.isEmpty ? defaults.homeWidgets : decoded
            } else {
                homeWidgets = try c.decodeIfPresent([HomeWidgetKind].self, forKey: .homeWidgets) ?? defaults.homeWidgets
            }

            menuBarEnabled = try c.decodeIfPresent(Bool.self, forKey: .menuBarEnabled) ?? defaults.menuBarEnabled
            focusSoundEnabled = try c.decodeIfPresent(Bool.self, forKey: .focusSoundEnabled) ?? defaults.focusSoundEnabled
            focusSoundVolume = try c.decodeIfPresent(Double.self, forKey: .focusSoundVolume) ?? defaults.focusSoundVolume
            dailyFocusGoal = try c.decodeIfPresent(Int.self, forKey: .dailyFocusGoal) ?? defaults.dailyFocusGoal
            dailyTaskCount = try c.decodeIfPresent(Int.self, forKey: .dailyTaskCount) ?? defaults.dailyTaskCount
            dailySummaryEnabled = try c.decodeIfPresent(Bool.self, forKey: .dailySummaryEnabled) ?? defaults.dailySummaryEnabled
            taskDefaultPriority = try c.decodeIfPresent(TaskPriority.self, forKey: .taskDefaultPriority) ?? defaults.taskDefaultPriority
            habitWeekStartsMonday = try c.decodeIfPresent(Bool.self, forKey: .habitWeekStartsMonday) ?? defaults.habitWeekStartsMonday
            autoExportStatistics = try c.decodeIfPresent(Bool.self, forKey: .autoExportStatistics) ?? defaults.autoExportStatistics
            aiPlaceholderStyle = try c.decodeIfPresent(AIPlaceholderStyle.self, forKey: .aiPlaceholderStyle) ?? defaults.aiPlaceholderStyle
            backendSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .backendSyncEnabled) ?? defaults.backendSyncEnabled
            backendBaseURL = try c.decodeIfPresent(String.self, forKey: .backendBaseURL) ?? defaults.backendBaseURL
            backendClientDeviceID = try c.decodeIfPresent(String.self, forKey: .backendClientDeviceID) ?? defaults.backendClientDeviceID
        }
    }

    func sharedSettingsSnapshot() -> SharedSettingsSnapshot {
        SharedSettingsSnapshot(
            accentHex: accentHex,
            focusSoundEnabled: focusSoundEnabled,
            dailyTaskCount: dailyTaskCount,
            dailySummaryEnabled: dailySummaryEnabled
        )
    }

    mutating func applySharedSettingsSnapshot(_ snapshot: SharedSettingsSnapshot) {
        accentHex = snapshot.accentHex
        focusSoundEnabled = snapshot.focusSoundEnabled
        dailyTaskCount = snapshot.dailyTaskCount
        dailySummaryEnabled = snapshot.dailySummaryEnabled
    }

    func cloudSnapshot() -> CloudSnapshot {
        CloudSnapshot(
            accentHex: accentHex,
            glassIntensity: glassIntensity,
            topBarOrder: topBarOrder,
            homeWidgets: homeWidgets,
            menuBarEnabled: menuBarEnabled,
            focusSoundEnabled: focusSoundEnabled,
            focusSoundVolume: focusSoundVolume,
            dailyFocusGoal: dailyFocusGoal,
            dailyTaskCount: dailyTaskCount,
            dailySummaryEnabled: dailySummaryEnabled,
            taskDefaultPriority: taskDefaultPriority,
            habitWeekStartsMonday: habitWeekStartsMonday,
            autoExportStatistics: autoExportStatistics,
            aiPlaceholderStyle: aiPlaceholderStyle,
            backendSyncEnabled: backendSyncEnabled,
            backendBaseURL: backendBaseURL,
            backendClientDeviceID: backendClientDeviceID
        )
    }

    mutating func applyCloudSnapshot(_ snapshot: CloudSnapshot) {
        accentHex = snapshot.accentHex
        glassIntensity = snapshot.glassIntensity
        topBarOrder = snapshot.topBarOrder
        homeWidgets = snapshot.homeWidgets
        menuBarEnabled = snapshot.menuBarEnabled
        focusSoundEnabled = snapshot.focusSoundEnabled
        focusSoundVolume = snapshot.focusSoundVolume
        dailyFocusGoal = snapshot.dailyFocusGoal
        dailyTaskCount = snapshot.dailyTaskCount
        dailySummaryEnabled = snapshot.dailySummaryEnabled
        taskDefaultPriority = snapshot.taskDefaultPriority
        habitWeekStartsMonday = snapshot.habitWeekStartsMonday
        autoExportStatistics = snapshot.autoExportStatistics
        aiPlaceholderStyle = snapshot.aiPlaceholderStyle
        backendSyncEnabled = snapshot.backendSyncEnabled
        backendBaseURL = snapshot.backendBaseURL
        backendClientDeviceID = snapshot.backendClientDeviceID
    }
}

enum CloudSyncStatus: Equatable {
    case checking
    case active
    case syncing
    case disabled
    case unavailable(String)
    case error(String)
}

private enum CloudSyncDomain: String, CaseIterable {
    case sharedSettings
    case macPlatformSettings
    case calendarSources
    case tasks
    case habits
    case focus
    case gamification

    var fileName: String {
        switch self {
        case .sharedSettings:
            return "shared_settings_sync.json"
        case .macPlatformSettings:
            return "mac_platform_settings_sync.json"
        case .calendarSources:
            return "calendar_sources_sync.json"
        default:
            return "mac_\(rawValue)_sync.json"
        }
    }

    var legacyFileNames: [String] {
        switch self {
        case .sharedSettings:
            return ["mobile_settings_sync.json"]
        case .macPlatformSettings:
            return ["mac_settings_sync.json"]
        default:
            return []
        }
    }
}

private struct CloudSyncMetadata: Codable {
    var modifiedAt: [String: Date]
    var lastSuccessfulSyncAt: Date?

    static let empty = CloudSyncMetadata(modifiedAt: [:], lastSuccessfulSyncAt: nil)
}

private struct CloudSyncEnvelope: Codable {
    var modifiedAt: Date
    var payloadData: Data
}

private struct CloudTasksPayload: Codable {
    var tasks: [TaskItem]
    var archivedTasks: [ArchivedTaskItem]
}

private struct CloudHabitsPayload: Codable {
    var habits: [HabitItem]
}

private struct CloudFocusPayload: Codable {
    var logs: [FocusLogEntry]
}

private struct CloudGamificationPayload: Codable {
    var snapshot: GamificationService.CloudSnapshot
}

private struct CloudSettingsPayload: Codable {
    var snapshot: MaddySettings.CloudSnapshot
}

private struct CloudSharedSettingsPayload: Codable {
    var snapshot: MaddySettings.SharedSettingsSnapshot
}

private struct CloudLegacyMobileSettingsSnapshot: Codable {
    var accentHex: String
    var soundEnabled: Bool
    var dailyTaskCount: Int?
    var dailySummaryEnabled: Bool?
}

private struct CloudCalendarSourcesPayload: Codable {
    var iCalSubscriptions: [ICalSubscription]
    var showGoogleCalendarEvents: Bool
    var showICalCalendarEvents: Bool
    var showTaskCalendarEntries: Bool
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

        let status = TaskStatus(rawValue: status ?? TaskStatus.backlog.rawValue) ?? .backlog
        let difficulty = TaskDifficulty(rawValue: difficulty ?? TaskDifficulty.medium.rawValue) ?? .medium
        let priority = TaskPriority(rawValue: priority ?? TaskPriority.medium.rawValue) ?? .medium
        let mappedSkills = (mappedSkills ?? [])
            .compactMap(TaskSkillTag.init(rawValue:))
        let createdDate = createdAt.flatMap { BackendDateFormatter.date(from: $0) } ?? Date()
        let updatedDate = clientUpdatedAt.flatMap { BackendDateFormatter.date(from: $0) }
            ?? updatedAt.flatMap { BackendDateFormatter.date(from: $0) }
            ?? createdDate

        return TaskItem(
            id: uuid,
            title: title ?? "",
            notes: "",
            dueDate: dueAt.flatMap { BackendDateFormatter.date(from: $0) },
            priority: priority,
            difficulty: difficulty,
            tags: tags ?? [],
            status: status,
            mappedSkills: mappedSkills.isEmpty ? [.execution] : mappedSkills,
            isDailyTask: isDailyTask ?? false,
            isRequiredDailyTask: isRequiredDailyTask ?? false,
            dailyDateKey: dailyDateKey,
            recurrence: .none,
            order: 0,
            createdAt: createdDate,
            updatedAt: updatedDate,
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
