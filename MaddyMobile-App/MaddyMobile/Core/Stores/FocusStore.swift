import Foundation
import Combine

// =====================================================
// MARK: - FocusStore
// [TAG: MOBILE_FOCUS_STORE]
// =====================================================

@MainActor
final class FocusStore: ObservableObject {
    struct CloudSnapshot: Codable {
        var selectedMode: FocusMode
        var customMinutes: Int
        var dailyGoalMinutes: Int
        var sessions: [FocusSession]
        var modifiedAt: Date
    }

    @Published var selectedMode: FocusMode = .pomodoro

    @Published var customMinutes: Int = 15 {
        didSet {
            guard isApplyingCloudSnapshot == false else { return }
            customMinutes = max(1, customMinutes)
            persistState()
            if selectedMode == .custom, isRunning == false {
                applyModeDefaults()
            }
            touchLocalMutation()
        }
    }

    @Published var dailyGoalMinutes: Int = 120 {
        didSet {
            guard isApplyingCloudSnapshot == false else { return }
            dailyGoalMinutes = max(10, dailyGoalMinutes)
            persistState()
            touchLocalMutation()
        }
    }

    @Published private(set) var totalSeconds: Int = 25 * 60
    @Published private(set) var remainingSeconds: Int = 25 * 60
    @Published private(set) var isRunning: Bool = false

    @Published private(set) var sessions: [FocusSession] {
        didSet {
            persistSessions()
            guard isApplyingCloudSnapshot == false else { return }
            touchLocalMutation()
        }
    }

    var onSessionRecorded: ((FocusSession) -> Void)?
    var onDataChanged: (() -> Void)?

    private let storage: LocalJSONStorage
    private var timerCancellable: AnyCancellable?
    private var sessionStartDate: Date?

    private struct PersistedState: Codable {
        var selectedMode: FocusMode?
        var dailyGoalMinutes: Int
        var customMinutes: Int
        var lastModifiedAt: Date?
    }

    private struct LegacyPersistedState: Codable {
        var dailyGoalMinutes: Int
        var customMinutes: Int
    }

    private let sessionsFile = "focus_sessions.json"
    private let stateFile = "focus_state.json"
    private(set) var lastModifiedAt: Date
    private var isApplyingCloudSnapshot = false

    init(storage: LocalJSONStorage = .shared) {
        self.storage = storage
        let loadedSessions = storage.load([FocusSession].self, from: sessionsFile, fallback: [])
        sessions = loadedSessions
        let sessionsDerivedModifiedAt = loadedSessions.map(\.endDate).max() ?? .distantPast

        if let loadedState = storage.loadIfPresent(PersistedState.self, from: stateFile) {
            dailyGoalMinutes = max(10, loadedState.dailyGoalMinutes)
            customMinutes = max(1, loadedState.customMinutes)
            selectedMode = loadedState.selectedMode ?? .pomodoro
            lastModifiedAt = loadedState.lastModifiedAt ?? sessionsDerivedModifiedAt
        } else if let legacyState = storage.loadIfPresent(LegacyPersistedState.self, from: stateFile) {
            dailyGoalMinutes = max(10, legacyState.dailyGoalMinutes)
            customMinutes = max(1, legacyState.customMinutes)
            selectedMode = .pomodoro
            lastModifiedAt = sessionsDerivedModifiedAt
        } else {
            dailyGoalMinutes = 120
            customMinutes = 15
            selectedMode = .pomodoro
            lastModifiedAt = sessionsDerivedModifiedAt
        }

        applyModeDefaults()
        persistState()
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }

    var timeText: String {
        let mm = remainingSeconds / 60
        let ss = remainingSeconds % 60
        return String(format: "%02d:%02d", mm, ss)
    }

    var todayFocusMinutes: Int {
        let calendar = Calendar.current
        return sessions
            .filter { calendar.isDateInToday($0.startDate) }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    func setMode(_ mode: FocusMode) {
        selectedMode = mode
        reset()
        touchLocalMutation()
    }

    func startPauseToggle() {
        if isRunning { pause() } else { start() }
    }

    func start() {
        guard isRunning == false else { return }
        if remainingSeconds <= 0 {
            reset()
        }
        if sessionStartDate == nil {
            sessionStartDate = Date()
        }
        isRunning = true

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    func pause() {
        isRunning = false
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    func reset() {
        pause()
        applyModeDefaults()
        sessionStartDate = nil
    }

    func completeNow() {
        guard let start = sessionStartDate else { return }
        let end = Date()
        let minutes = max(1, Int(round(Double(totalSeconds - remainingSeconds) / 60.0)))
        let entry = FocusSession(id: UUID(), startDate: start, endDate: end, durationMinutes: minutes, mode: selectedMode)
        sessions.insert(entry, at: 0)
        onSessionRecorded?(entry)
        sessionStartDate = nil
    }

    func cloudSnapshot() -> CloudSnapshot {
        CloudSnapshot(
            selectedMode: selectedMode,
            customMinutes: customMinutes,
            dailyGoalMinutes: dailyGoalMinutes,
            sessions: sessions,
            modifiedAt: lastModifiedAt
        )
    }

    func applyCloudSnapshot(_ snapshot: CloudSnapshot) {
        guard snapshot.modifiedAt > lastModifiedAt else { return }

        isApplyingCloudSnapshot = true
        selectedMode = snapshot.selectedMode
        customMinutes = max(1, snapshot.customMinutes)
        dailyGoalMinutes = max(10, snapshot.dailyGoalMinutes)
        sessions = snapshot.sessions
        lastModifiedAt = snapshot.modifiedAt
        isApplyingCloudSnapshot = false

        if isRunning == false {
            applyModeDefaults()
        }
        persistState()
    }

    private func tick() {
        guard isRunning else { return }

        if remainingSeconds > 0 {
            remainingSeconds -= 1
        }

        if remainingSeconds <= 0 {
            pause()
            completeNow()
            applyModeDefaults()
        }
    }

    private func applyModeDefaults() {
        let minutes = selectedMode == .pomodoro ? 25 : customMinutes
        totalSeconds = max(1, minutes * 60)
        remainingSeconds = totalSeconds
        persistState()
    }

    private func touchLocalMutation() {
        guard isApplyingCloudSnapshot == false else { return }
        lastModifiedAt = Date()
        persistState()
        onDataChanged?()
    }

    private func persistSessions() {
        storage.save(sessions, to: sessionsFile)
    }

    private func persistState() {
        let state = PersistedState(
            selectedMode: selectedMode,
            dailyGoalMinutes: dailyGoalMinutes,
            customMinutes: customMinutes,
            lastModifiedAt: lastModifiedAt
        )
        storage.save(state, to: stateFile)
    }
}
