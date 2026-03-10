//
//  AppDomainModels.swift
//  MaddyV2
//
//  Extracted domain models, feature view models and persistence helpers from AppState.
//

import SwiftUI
import Combine
import Foundation

// MARK: - AI Placeholder Style
// [TAG: AI_PLACEHOLDER_STYLE]
// =====================================================

enum AIPlaceholderStyle: String, Codable, CaseIterable, Identifiable {
    case orb
    case face
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .orb:
            return "Orb"
        case .face:
            return "Face"
        case .status:
            return "Status Card"
        }
    }
}

// =====================================================
// MARK: - Calendar Subscription Model
// [TAG: V2_CALENDAR_SUBSCRIPTION_MODEL]
// =====================================================

struct ICalSubscription: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var urlString: String
    var isEnabled: Bool
    var lastRefreshAt: Date?
    var lastError: String?
}

// =====================================================
// MARK: - Task Models
// [TAG: V2_TASK_MODELS]
// =====================================================

enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var sortWeight: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

enum TaskDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    var xpReward: Int {
        switch self {
        case .easy: return 8
        case .medium: return 12
        case .hard: return 18
        }
    }
}

enum TaskSkillTag: String, Codable, CaseIterable, Identifiable {
    case focus
    case execution
    case routine
    case reliability

    var id: String { rawValue }

    var title: String { rawValue.capitalized }
}

enum TaskStatus: String, Codable, Identifiable, CaseIterable {
    case backlog
    case inProgress
    case done
    case missed

    var id: String { rawValue }

    static var allCases: [TaskStatus] {
        [.backlog, .inProgress, .done]
    }

    var title: String {
        switch self {
        case .backlog: return "Backlog"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        case .missed: return "Missed"
        }
    }
}

enum TaskRecurrence: String, Codable, CaseIterable, Identifiable {
    case none
    case daily
    case weekly
    case monthly

    var id: String { rawValue }
}

struct TaskItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var priority: TaskPriority
    var difficulty: TaskDifficulty
    var tags: [String]
    var status: TaskStatus
    var mappedSkills: [TaskSkillTag]
    var isDailyTask: Bool
    var isRequiredDailyTask: Bool
    var dailyDateKey: String?
    var recurrence: TaskRecurrence
    var order: Int
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(
        id: UUID,
        title: String,
        notes: String,
        dueDate: Date?,
        priority: TaskPriority,
        difficulty: TaskDifficulty,
        tags: [String],
        status: TaskStatus,
        mappedSkills: [TaskSkillTag],
        isDailyTask: Bool,
        isRequiredDailyTask: Bool,
        dailyDateKey: String?,
        recurrence: TaskRecurrence,
        order: Int,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
        self.difficulty = difficulty
        self.tags = tags
        self.status = status
        self.mappedSkills = mappedSkills
        self.isDailyTask = isDailyTask
        self.isRequiredDailyTask = isRequiredDailyTask
        self.dailyDateKey = dailyDateKey
        self.recurrence = recurrence
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    static func makeEmpty(defaultPriority: TaskPriority) -> TaskItem {
        TaskItem(
            id: UUID(),
            title: "",
            notes: "",
            dueDate: nil,
            priority: defaultPriority,
            difficulty: .medium,
            tags: [],
            status: .backlog,
            mappedSkills: [.execution],
            isDailyTask: false,
            isRequiredDailyTask: false,
            dailyDateKey: nil,
            recurrence: .none,
            order: 0,
            createdAt: Date(),
            updatedAt: Date(),
            completedAt: nil
        )
    }

    var effectiveDailyKey: String {
        if let dailyDateKey, dailyDateKey.isEmpty == false {
            return dailyDateKey
        }
        return Self.dayKey(Date())
    }

    var isOverdue: Bool {
        guard let dueDate else { return false }
        return dueDate < Date() && status != .done
    }

    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // Backward-compatible decode for older persisted tasks that may miss fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        priority = try c.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .medium
        difficulty = try c.decodeIfPresent(TaskDifficulty.self, forKey: .difficulty) ?? .medium
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        status = try c.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .backlog
        mappedSkills = try c.decodeIfPresent([TaskSkillTag].self, forKey: .mappedSkills) ?? [.execution]
        isDailyTask = try c.decodeIfPresent(Bool.self, forKey: .isDailyTask) ?? false
        isRequiredDailyTask = try c.decodeIfPresent(Bool.self, forKey: .isRequiredDailyTask) ?? false
        dailyDateKey = try c.decodeIfPresent(String.self, forKey: .dailyDateKey)
        recurrence = try c.decodeIfPresent(TaskRecurrence.self, forKey: .recurrence) ?? .none
        order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

struct ArchivedTaskItem: Identifiable, Codable, Equatable {
    var id: UUID
    var task: TaskItem
    var archivedAt: Date
    var sourceStatus: TaskStatus
}

// =====================================================
// MARK: - Daily Task Library
// [TAG: V2_DAILY_TASK_LIBRARY]
// =====================================================

struct DailyTaskLibraryItem: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var subtitle: String?
    var pack: String
    var difficulty: TaskDifficulty
    var preferredSkills: [TaskSkillTag]
    var requiredByDefault: Bool
    var systemGenerated: Bool
    var tags: [String]

    func makeTask(dayKey: String, date: Date) -> TaskItem {
        let mergedTags = Array(Set(["daily", "pack", "pack:\(pack)"] + tags)).sorted()
        return TaskItem(
            id: UUID(),
            title: title,
            notes: subtitle ?? "",
            dueDate: nil,
            priority: .medium,
            difficulty: difficulty,
            tags: mergedTags,
            status: .backlog,
            mappedSkills: preferredSkills.isEmpty ? [.reliability] : Array(preferredSkills.prefix(2)),
            isDailyTask: true,
            isRequiredDailyTask: requiredByDefault,
            dailyDateKey: dayKey,
            recurrence: .none,
            order: 0,
            createdAt: date,
            updatedAt: date,
            completedAt: nil
        )
    }
}

enum DailyTaskLibrary {
    static let knownPacks: [String] = ["productivity", "routine", "cleanSpace", "reset", "student", "discipline"]

    static let items: [DailyTaskLibraryItem] = [
        .init(id: "prod_important_morning", title: "Complete 1 important task before 12:00", subtitle: "Prioritize impact early in the day.", pack: "productivity", difficulty: .medium, preferredSkills: [.execution, .reliability], requiredByDefault: true, systemGenerated: true, tags: ["important", "morning", "execution-balance"]),
        .init(id: "prod_two_medium", title: "Finish 2 medium tasks", subtitle: "Convert planning into shipped output.", pack: "productivity", difficulty: .medium, preferredSkills: [.execution], requiredByDefault: true, systemGenerated: true, tags: ["throughput", "execution-balance"]),
        .init(id: "prod_backlog_three", title: "Clear 3 small backlog items", subtitle: "Reduce carry-over and keep your board clean.", pack: "productivity", difficulty: .easy, preferredSkills: [.execution, .reliability], requiredByDefault: false, systemGenerated: true, tags: ["backlog", "cleanup"]),
        .init(id: "prod_avoidance_task", title: "Do 1 task you have been avoiding", subtitle: "Pick the one you've postponed the longest.", pack: "productivity", difficulty: .hard, preferredSkills: [.execution, .focus], requiredByDefault: false, systemGenerated: true, tags: ["avoidance", "courage"]),
        .init(id: "prod_priority_reset", title: "Do a short reset and review priorities", subtitle: "Spend 10 minutes re-ordering your top tasks.", pack: "productivity", difficulty: .easy, preferredSkills: [.reliability], requiredByDefault: false, systemGenerated: true, tags: ["planning", "reset"]),

        .init(id: "routine_required_habits", title: "Complete all required habits today", subtitle: "No required habit misses for the day.", pack: "routine", difficulty: .medium, preferredSkills: [.routine, .reliability], requiredByDefault: true, systemGenerated: true, tags: ["habit", "consistency", "routine-recovery"]),
        .init(id: "routine_morning_anchor", title: "Finish your morning routine before lunch", subtitle: "Lock in your baseline routine early.", pack: "routine", difficulty: .medium, preferredSkills: [.routine], requiredByDefault: true, systemGenerated: true, tags: ["morning", "habit"]),
        .init(id: "routine_evening_reset", title: "Complete your evening reset routine", subtitle: "Close the day with a clean handoff for tomorrow.", pack: "routine", difficulty: .easy, preferredSkills: [.routine, .reliability], requiredByDefault: false, systemGenerated: true, tags: ["evening", "routine-recovery"]),
        .init(id: "routine_habit_streak", title: "Advance one habit streak today", subtitle: "Complete at least one habit currently on a streak.", pack: "routine", difficulty: .easy, preferredSkills: [.routine], requiredByDefault: false, systemGenerated: true, tags: ["streak", "habit"]),

        .init(id: "clean_desk_ten", title: "Spend 10 minutes organizing your desk", subtitle: "Remove clutter and reset your work surface.", pack: "cleanSpace", difficulty: .easy, preferredSkills: [.routine], requiredByDefault: false, systemGenerated: true, tags: ["environment", "cleanup"]),
        .init(id: "clean_inbox_zero", title: "Clear your top 10 inbox items", subtitle: "Email/messages/notes count.", pack: "cleanSpace", difficulty: .medium, preferredSkills: [.execution], requiredByDefault: false, systemGenerated: true, tags: ["digital", "cleanup"]),
        .init(id: "clean_workspace_reset", title: "Reset one digital workspace", subtitle: "Files, desktop, or project folders.", pack: "cleanSpace", difficulty: .easy, preferredSkills: [.reliability], requiredByDefault: false, systemGenerated: true, tags: ["digital", "reset"]),
        .init(id: "clean_quick_declutter", title: "Do a 5-minute quick declutter sprint", subtitle: "Set a timer and clean one area only.", pack: "cleanSpace", difficulty: .easy, preferredSkills: [.routine], requiredByDefault: false, systemGenerated: true, tags: ["physical", "recovery-reset"]),

        .init(id: "reset_focus_25", title: "Do 1 focused 25-minute session", subtitle: "Single deep block with no context switching.", pack: "reset", difficulty: .medium, preferredSkills: [.focus], requiredByDefault: true, systemGenerated: true, tags: ["focus-gap", "recovery-reset"]),
        .init(id: "reset_focus_goal", title: "Reach your focus goal today", subtitle: "Hit your current daily focus target.", pack: "reset", difficulty: .hard, preferredSkills: [.focus, .reliability], requiredByDefault: false, systemGenerated: true, tags: ["focus-gap", "goal"]),
        .init(id: "reset_one_finish", title: "Finish 1 task start-to-finish in one sitting", subtitle: "No task hopping during this one.", pack: "reset", difficulty: .medium, preferredSkills: [.focus, .execution], requiredByDefault: false, systemGenerated: true, tags: ["execution-balance", "recovery-reset"]),
        .init(id: "reset_reliability_task", title: "Complete a task mapped to Reliability", subtitle: "Choose a consistency-heavy task.", pack: "reset", difficulty: .easy, preferredSkills: [.reliability], requiredByDefault: false, systemGenerated: true, tags: ["reliability-rebuild"]),

        .init(id: "student_study_block", title: "Complete one focused study block", subtitle: "25-45 minutes of uninterrupted study.", pack: "student", difficulty: .medium, preferredSkills: [.focus], requiredByDefault: true, systemGenerated: true, tags: ["study", "focus-gap"]),
        .init(id: "student_summary", title: "Write a short summary of one concept", subtitle: "5-8 bullet points is enough.", pack: "student", difficulty: .medium, preferredSkills: [.execution], requiredByDefault: false, systemGenerated: true, tags: ["study", "execution-balance"]),
        .init(id: "student_review_notes", title: "Review and clean up your notes for 15 minutes", subtitle: "Organize, rename, and mark action points.", pack: "student", difficulty: .easy, preferredSkills: [.routine], requiredByDefault: false, systemGenerated: true, tags: ["study", "cleanup"]),
        .init(id: "student_assignment_push", title: "Make visible progress on one assignment", subtitle: "Complete one concrete sub-step.", pack: "student", difficulty: .hard, preferredSkills: [.execution, .reliability], requiredByDefault: false, systemGenerated: true, tags: ["study", "important"]),

        .init(id: "discipline_daily_complete", title: "Complete all daily tasks today", subtitle: "Finish the whole daily set.", pack: "discipline", difficulty: .hard, preferredSkills: [.reliability], requiredByDefault: true, systemGenerated: true, tags: ["consistency", "reliability-rebuild"]),
        .init(id: "discipline_no_overdue", title: "Resolve 1 overdue task", subtitle: "Bring one overdue item back to done.", pack: "discipline", difficulty: .medium, preferredSkills: [.reliability, .execution], requiredByDefault: false, systemGenerated: true, tags: ["overdue", "reliability-rebuild"]),
        .init(id: "discipline_three_done", title: "Complete 3 tasks with clean handoff notes", subtitle: "Keep your progress verifiable.", pack: "discipline", difficulty: .hard, preferredSkills: [.execution, .reliability], requiredByDefault: false, systemGenerated: true, tags: ["consistency", "execution-balance"]),
        .init(id: "discipline_follow_plan", title: "Stick to your top 3 priorities for the day", subtitle: "No extra commitments until those are done.", pack: "discipline", difficulty: .medium, preferredSkills: [.reliability], requiredByDefault: false, systemGenerated: true, tags: ["planning", "reliability-rebuild"])
    ]

    static func tasks(
        pack: String? = nil,
        count: Int,
        dayKey: String,
        date: Date,
        excludingTitles: Set<String> = [],
        matchingAnyTags: [String] = []
    ) -> [TaskItem] {
        let normalizedExclusions = Set(excludingTitles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let loweredTags = Set(matchingAnyTags.map { $0.lowercased() })
        let sanitizedPack = pack.flatMap { knownPacks.contains($0) ? $0 : nil }

        let pool = items.filter { item in
            if let sanitizedPack, item.pack != sanitizedPack { return false }
            if normalizedExclusions.contains(item.title.lowercased()) { return false }
            if loweredTags.isEmpty { return true }
            return item.tags.contains { loweredTags.contains($0.lowercased()) }
        }

        let selected = Array(pool.shuffled().prefix(max(0, count)))
        return selected.map { $0.makeTask(dayKey: dayKey, date: date) }
    }
}

// =====================================================
// MARK: - Habit Models
// [TAG: V2_HABIT_MODELS]
// =====================================================

enum HabitKind: String, Codable, CaseIterable, Identifiable {
    case timeBased
    case quantityBased

    var id: String { rawValue }

    var unitLabel: String {
        switch self {
        case .timeBased: return "min"
        case .quantityBased: return "count"
        }
    }
}

struct HabitItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var symbol: String
    var accentHex: String
    var kind: HabitKind
    var targetPerDay: Int
    var tags: [String]
    var scheduledWeekdays: [Int]
    var history: [String: Int]

    static let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    static func makeEmpty() -> HabitItem {
        HabitItem(
            id: UUID(),
            title: "",
            symbol: "leaf.fill",
            accentHex: "#24C483",
            kind: .quantityBased,
            targetPerDay: 1,
            tags: [],
            scheduledWeekdays: [2, 3, 4, 5, 6],
            history: [:]
        )
    }
}

// =====================================================
// MARK: - Focus Models
// [TAG: V2_FOCUS_MODELS]
// =====================================================

enum FocusPhase: String, Codable, CaseIterable, Identifiable {
    case work
    case shortBreak
    case longBreak
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .work: return "Work"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        case .custom: return "Custom"
        }
    }

    var espIdentifier: String {
        switch self {
        case .work: return "work"
        case .shortBreak: return "short"
        case .longBreak: return "long"
        case .custom: return "custom"
        }
    }
}

struct FocusLogEntry: Identifiable, Codable {
    var id: UUID
    var phase: FocusPhase
    var startedAt: Date
    var durationSeconds: Int
    var source: String
}

// =====================================================
// MARK: - Home Models
// [TAG: V2_HOME_MODELS]
// =====================================================

enum HomeWidgetKind: String, Codable, CaseIterable, Identifiable {
    case focus
    case tasks
    case habits
    case serial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .tasks: return "Tasks"
        case .habits: return "Habits"
        case .serial: return "ESP"
        }
    }
}

// =====================================================
// MARK: - FocusViewModel
// [TAG: V2_FOCUS_VM]
// =====================================================

@MainActor
final class FocusViewModel: ObservableObject {
    @Published var phase: FocusPhase = .work
    @Published var remainingSeconds: Int = 25 * 60
    @Published var totalSeconds: Int = 25 * 60
    @Published var running: Bool = false

    @Published var customMinutes: Int = 15
    @Published var pomodoroWorkMinutes: Int = 25
    @Published var pomodoroShortBreakMinutes: Int = 5
    @Published var pomodoroLongBreakMinutes: Int = 15
    @Published var pomodoroCycleLength: Int = 4

    @Published var dailyGoal: Int = 8
    @Published var logs: [FocusLogEntry]

    var onTick: ((FocusPhase, Int, Int, Bool) -> Void)?
    var onSessionCompleted: ((FocusLogEntry) -> Void)?

    private var timer: AnyCancellable?
    private var completedWorkSessions = 0
    private let persist: ([FocusLogEntry]) -> Void

    init(logs: [FocusLogEntry], persist: @escaping ([FocusLogEntry]) -> Void) {
        self.logs = logs
        self.persist = persist
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1 - (Double(remainingSeconds) / Double(totalSeconds))
    }

    var todaySessions: Int {
        logs.filter { Calendar.current.isDateInToday($0.startedAt) && $0.phase == .work }.count
    }

    var todayFocusMinutes: Int {
        logs.reduce(0) { partial, entry in
            guard Calendar.current.isDateInToday(entry.startedAt) else { return partial }
            guard entry.phase == .work || entry.phase == .custom else { return partial }
            return partial + max(1, entry.durationSeconds / 60)
        }
    }

    var weekMinutes: Int {
        minutes(for: .weekOfYear)
    }

    var monthMinutes: Int {
        minutes(for: .month)
    }

    var streakDays: Int {
        var streak = 0
        var day = Calendar.current.startOfDay(for: Date())

        while true {
            let hasSession = logs.contains {
                $0.phase == .work && Calendar.current.isDate($0.startedAt, inSameDayAs: day)
            }
            if hasSession {
                streak += 1
            } else {
                break
            }
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: day) else {
                break
            }
            day = previous
        }

        return streak
    }

    func startFromTask(_ title: String) {
        phase = .work
        reset(to: pomodoroWorkMinutes * 60)
        toggleRunning(source: "task:\(title)")
    }

    func toggleRunning(source: String = "manual") {
        running.toggle()
        if running {
            startTimer(source: source)
        } else {
            timer?.cancel()
        }
        onTick?(phase, remainingSeconds, totalSeconds, running)
    }

    func resetCurrent() {
        running = false
        timer?.cancel()
        switch phase {
        case .work:
            reset(to: pomodoroWorkMinutes * 60)
        case .shortBreak:
            reset(to: pomodoroShortBreakMinutes * 60)
        case .longBreak:
            reset(to: pomodoroLongBreakMinutes * 60)
        case .custom:
            reset(to: customMinutes * 60)
        }
        onTick?(phase, remainingSeconds, totalSeconds, running)
    }

    func setPomodoroPhase(_ newPhase: FocusPhase) {
        phase = newPhase
        running = false
        timer?.cancel()

        switch newPhase {
        case .work:
            reset(to: pomodoroWorkMinutes * 60)
        case .shortBreak:
            reset(to: pomodoroShortBreakMinutes * 60)
        case .longBreak:
            reset(to: pomodoroLongBreakMinutes * 60)
        case .custom:
            reset(to: customMinutes * 60)
        }
        onTick?(phase, remainingSeconds, totalSeconds, running)
    }

    func applyCustomTimer() {
        setPomodoroPhase(.custom)
    }

    private func startTimer(source: String) {
        timer?.cancel()
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.running else { return }

                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                    self.onTick?(self.phase, self.remainingSeconds, self.totalSeconds, self.running)
                    return
                }

                self.finishCurrentPhase(source: source)
            }
    }

    private func finishCurrentPhase(source: String) {
        running = false
        timer?.cancel()

        let duration = totalSeconds
        let now = Date()

        if phase == .work || phase == .custom {
            let entry = FocusLogEntry(id: UUID(), phase: phase, startedAt: now, durationSeconds: duration, source: source)
            logs.append(entry)
            persist(logs)
            onSessionCompleted?(entry)
        }

        if phase == .work {
            completedWorkSessions += 1
            if completedWorkSessions % pomodoroCycleLength == 0 {
                setPomodoroPhase(.longBreak)
            } else {
                setPomodoroPhase(.shortBreak)
            }
        } else if phase == .shortBreak || phase == .longBreak {
            setPomodoroPhase(.work)
        }

        onTick?(phase, remainingSeconds, totalSeconds, running)
    }

    private func reset(to seconds: Int) {
        totalSeconds = max(1, seconds)
        remainingSeconds = max(1, seconds)
    }

    private func minutes(for component: Calendar.Component) -> Int {
        guard let start = Calendar.current.dateInterval(of: component, for: Date())?.start else {
            return 0
        }

        let total = logs
            .filter { $0.phase == .work && $0.startedAt >= start }
            .reduce(0) { $0 + ($1.durationSeconds / 60) }

        return total
    }
}

// =====================================================
// MARK: - TasksViewModel
// [TAG: V2_TASKS_VM]
// =====================================================

@MainActor
final class TasksViewModel: ObservableObject {
    @Published var tasks: [TaskItem]
    @Published var archivedTasks: [ArchivedTaskItem]
    @Published var draft: TaskItem
    @Published var validationMessage: String?
    @Published var latestArchiveNotice: ArchiveNotice?

    struct ArchiveNotice: Identifiable, Equatable {
        var id = UUID()
        var archiveID: UUID
        var title: String
    }

    var onStartFocus: ((TaskItem) -> Void)?
    var onTaskCompleted: ((TaskItem) -> Void)?
    var onDailyTaskMissed: ((TaskItem) -> Void)?

    private let persist: ([TaskItem], [ArchivedTaskItem]) -> Void

    init(tasks: [TaskItem], archivedTasks: [ArchivedTaskItem], persist: @escaping ([TaskItem], [ArchivedTaskItem]) -> Void) {
        self.tasks = tasks
        self.archivedTasks = archivedTasks
        self.persist = persist
        self.draft = TaskItem.makeEmpty(defaultPriority: .medium)

        if migrateDoneTasksIntoArchive() {
            persistAll()
        }
    }

    func resetDraft(defaultPriority: TaskPriority) {
        draft = TaskItem.makeEmpty(defaultPriority: defaultPriority)
        validationMessage = nil
    }

    func beginEditing(_ task: TaskItem) {
        draft = task
        validationMessage = nil
    }

    func createTask(defaultPriority: TaskPriority) -> Bool {
        saveDraft(defaultPriority: defaultPriority)
    }

    @discardableResult
    func saveDraft(defaultPriority: TaskPriority) -> Bool {
        validationMessage = nil

        let cleanTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanTitle.isEmpty == false else {
            validationMessage = "Task title is required."
            return false
        }

        if draft.priority == .high && draft.dueDate == nil {
            validationMessage = "High priority tasks require a due date."
            return false
        }

        var task = draft
        task.title = cleanTitle
        task.updatedAt = Date()
        if task.isDailyTask, task.dailyDateKey == nil {
            task.dailyDateKey = TaskItem.dayKey(Date())
        }
        var previousStatus: TaskStatus?

        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            previousStatus = tasks[index].status
            task.order = tasks[index].order
            task.createdAt = tasks[index].createdAt
            task.updatedAt = Date()
            tasks[index] = task
        } else {
            task.order = nextOrder(in: task.status)
            task.createdAt = Date()
            task.updatedAt = task.createdAt
            tasks.append(task)
        }

        if task.status == .done {
            if previousStatus != .done {
                task.completedAt = task.completedAt ?? Date()
                spawnRecurringTaskIfNeeded(from: task)
                onTaskCompleted?(task)
            }
            archive(task, sourceStatus: previousStatus ?? .backlog, announce: true)
            if let previousStatus, previousStatus != .done {
                normalizeOrders(for: previousStatus)
            }
            persistAll()
            resetDraft(defaultPriority: defaultPriority)
            return true
        }

        if let previousStatus, previousStatus != task.status, previousStatus != .done {
            normalizeOrders(for: previousStatus)
        }

        normalizeOrders(for: task.status)
        persistAll()
        resetDraft(defaultPriority: defaultPriority)
        return true
    }

    func deleteTasks(_ offsets: IndexSet, status: TaskStatus) {
        let scopedIDs = tasks(for: status).map(\.id)
        let idsToDelete = offsets.compactMap { scopedIDs[safe: $0] }
        tasks.removeAll { idsToDelete.contains($0.id) }
        persistAll()
    }

    func moveTasks(in status: TaskStatus, from source: IndexSet, to destination: Int) {
        var scoped = tasks(for: status)
        scoped.move(fromOffsets: source, toOffset: destination)

        for (index, task) in scoped.enumerated() {
            if let globalIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[globalIndex].order = index
            }
        }

        persistAll()
    }

    func setStatus(_ status: TaskStatus, for task: TaskItem) {
        moveTask(task.id, to: status, before: nil)
    }

    func startFocus(for task: TaskItem) {
        onStartFocus?(task)
    }

    func tasks(for status: TaskStatus) -> [TaskItem] {
        tasks
            .filter { $0.status == status }
            .sorted(by: laneComparator)
    }

    func dailyTasks(for date: Date = Date()) -> [TaskItem] {
        let dayKey = TaskItem.dayKey(date)
        return tasks.filter {
            $0.isDailyTask &&
            $0.effectiveDailyKey == dayKey &&
            $0.status != .done &&
            $0.status != .missed
        }
    }

    func completedDailyTasks(for date: Date = Date()) -> [TaskItem] {
        let dayKey = TaskItem.dayKey(date)
        return archivedTasks.map(\.task).filter {
            $0.isDailyTask &&
            $0.effectiveDailyKey == dayKey &&
            $0.status == .done
        }
    }

    func completedNormalTasksCount(for date: Date = Date()) -> Int {
        let calendar = Calendar.current
        return archivedTasks.reduce(into: 0) { partial, archived in
            guard archived.task.isDailyTask == false else { return }
            guard let completedAt = archived.task.completedAt else { return }
            guard calendar.isDate(completedAt, inSameDayAs: date) else { return }
            partial += 1
        }
    }

    func delete(taskID: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let lane = tasks[idx].status
        tasks.remove(at: idx)
        normalizeOrders(for: lane)
        persistAll()
    }

    func deleteArchived(archiveID: UUID) {
        archivedTasks.removeAll { $0.id == archiveID }
        persistAll()
    }

    func clearArchive() {
        guard archivedTasks.isEmpty == false else { return }
        archivedTasks.removeAll()
        persistAll()
    }

    func restoreArchived(archiveID: UUID) {
        guard let index = archivedTasks.firstIndex(where: { $0.id == archiveID }) else { return }
        let entry = archivedTasks.remove(at: index)
        var restored = entry.task

        let restoredStatus: TaskStatus = entry.sourceStatus == .done ? .backlog : entry.sourceStatus
        restored.status = restoredStatus
        if restoredStatus != .done {
            restored.completedAt = nil
        }
        restored.order = nextOrder(in: restoredStatus)

        tasks.append(restored)
        normalizeOrders(for: restoredStatus)
        persistAll()
    }

    func undoArchive(archiveID: UUID) {
        restoreArchived(archiveID: archiveID)
    }

    func moveTask(_ taskID: UUID, to newStatus: TaskStatus, before beforeID: UUID?) {
        guard let movingIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return }

        let previousStatus = tasks[movingIndex].status

        if newStatus == .done {
            var completed = tasks[movingIndex]
            completed.status = .done
            completed.completedAt = completed.completedAt ?? Date()

            if previousStatus != .done {
                spawnRecurringTaskIfNeeded(from: completed)
                onTaskCompleted?(completed)
            }

            archive(completed, sourceStatus: previousStatus, announce: true)
            if previousStatus != .done {
                normalizeOrders(for: previousStatus)
            }
            persistAll()
            return
        }

        var moving = tasks[movingIndex]
        moving.status = newStatus
        moving.updatedAt = Date()

        if newStatus != .done {
            moving.completedAt = nil
        }

        tasks[movingIndex] = moving

        var laneIDs = tasks(for: newStatus).map(\.id).filter { $0 != taskID }
        if let beforeID, let insertIndex = laneIDs.firstIndex(of: beforeID) {
            laneIDs.insert(taskID, at: insertIndex)
        } else {
            laneIDs.append(taskID)
        }

        for (idx, id) in laneIDs.enumerated() {
            guard let global = tasks.firstIndex(where: { $0.id == id }) else { continue }
            tasks[global].status = newStatus
            tasks[global].order = idx
            tasks[global].updatedAt = Date()
        }

        if previousStatus != newStatus {
            normalizeOrders(for: previousStatus)
        }

        persistAll()
    }

    func applyDailyRollover(now: Date = Date()) {
        let currentDayKey = TaskItem.dayKey(now)
        let staleDaily = tasks.filter {
            $0.isDailyTask &&
            $0.effectiveDailyKey != currentDayKey &&
            $0.status != .done &&
            $0.status != .missed
        }
        guard staleDaily.isEmpty == false else { return }

        for task in staleDaily {
            var missed = task
            missed.status = .missed
            missed.updatedAt = now
            tasks.removeAll { $0.id == missed.id }
            archivedTasks.insert(
                ArchivedTaskItem(
                    id: UUID(),
                    task: missed,
                    archivedAt: now,
                    sourceStatus: .missed
                ),
                at: 0
            )
            onDailyTaskMissed?(missed)
        }
        persistAll()
    }

    func ensureDailyTaskCapacity(count: Int, templates: [TaskItem] = [], date: Date = Date()) {
        let targetCount = max(1, count)
        let dayKey = TaskItem.dayKey(date)
        let existing = dailyTasks(for: date)
        let needed = max(0, targetCount - existing.count)
        guard needed > 0 else { return }

        var generated: [TaskItem] = []

        if templates.isEmpty == false {
            for template in templates.prefix(needed) {
                var clone = template
                clone.id = UUID()
                clone.status = .backlog
                clone.order = nextOrder(in: .backlog)
                clone.dailyDateKey = dayKey
                clone.isDailyTask = true
                clone.createdAt = date
                clone.updatedAt = date
                clone.completedAt = nil
                generated.append(clone)
            }
        }

        let existingTitles = Set((existing + generated).map { $0.title.lowercased() })
        let fallback = DailyTaskLibrary.tasks(
            pack: nil,
            count: max(0, needed - generated.count),
            dayKey: dayKey,
            date: date,
            excludingTitles: existingTitles
        )
        generated.append(contentsOf: fallback)

        while generated.count < needed {
            let refill = DailyTaskLibrary.tasks(pack: nil, count: 1, dayKey: dayKey, date: date)
            guard let extra = refill.first else { break }
            generated.append(extra)
        }

        let baseOrder = nextOrder(in: .backlog)
        generated = generated.enumerated().map { index, task in
            var copy = task
            copy.order = baseOrder + index
            return copy
        }

        tasks.append(contentsOf: generated)
        normalizeOrders(for: .backlog)
        persistAll()
    }

    private func spawnRecurringTaskIfNeeded(from completed: TaskItem) {
        guard completed.recurrence != .none else { return }

        var next = completed
        next.id = UUID()
        next.status = .backlog
        next.completedAt = nil
        next.createdAt = Date()
        next.updatedAt = next.createdAt
        next.order = nextOrder(in: .backlog)

        if let due = completed.dueDate {
            let component: Calendar.Component
            let delta: Int

            switch completed.recurrence {
            case .daily:
                component = .day
                delta = 1
            case .weekly:
                component = .weekOfYear
                delta = 1
            case .monthly:
                component = .month
                delta = 1
            case .none:
                component = .day
                delta = 0
            }

            next.dueDate = Calendar.current.date(byAdding: component, value: delta, to: due)
        }

        tasks.append(next)
        normalizeOrders(for: .backlog)
    }

    private func migrateDoneTasksIntoArchive() -> Bool {
        let finished = tasks.filter { $0.status == .done }
        guard finished.isEmpty == false else { return false }

        for task in finished {
            archive(task, sourceStatus: .backlog, announce: false)
        }
        normalizeOrders(for: .backlog)
        normalizeOrders(for: .inProgress)
        return true
    }

    // =====================================================
    // MARK: - Done Auto Remove / Archive
    // [TAG: TASK_DONE_AUTO_REMOVE]
    // =====================================================

    private func archive(_ task: TaskItem, sourceStatus: TaskStatus, announce: Bool) {
        var archivedTask = task
        archivedTask.status = .done
        archivedTask.completedAt = archivedTask.completedAt ?? Date()
        archivedTask.updatedAt = Date()

        tasks.removeAll { $0.id == archivedTask.id }

        let archived = ArchivedTaskItem(
            id: UUID(),
            task: archivedTask,
            archivedAt: Date(),
            sourceStatus: sourceStatus
        )
        archivedTasks.insert(archived, at: 0)

        if announce {
            latestArchiveNotice = ArchiveNotice(archiveID: archived.id, title: archivedTask.title)
        }
    }

    private func persistAll() {
        persist(tasks, archivedTasks)
    }

    private func normalizeOrders(for status: TaskStatus) {
        let ids = tasks(for: status).map(\.id)
        for (index, id) in ids.enumerated() {
            guard let global = tasks.firstIndex(where: { $0.id == id }) else { continue }
            tasks[global].order = index
        }
    }

    private func laneComparator(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return smartComparator(lhs, rhs)
    }

    private func smartComparator(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }

        if lhs.priority.sortWeight != rhs.priority.sortWeight {
            return lhs.priority.sortWeight < rhs.priority.sortWeight
        }

        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }

        return lhs.createdAt < rhs.createdAt
    }

    private func nextOrder(in status: TaskStatus) -> Int {
        tasks.filter { $0.status == status }.map(\.order).max().map { $0 + 1 } ?? 0
    }
}

// =====================================================
// MARK: - HabitsViewModel
// [TAG: V2_HABITS_VM]
// =====================================================

@MainActor
final class HabitsViewModel: ObservableObject {
    @Published var habits: [HabitItem]
    @Published var draft: HabitItem = .makeEmpty()
    var onHabitCompleted: ((HabitItem) -> Void)?

    private let persist: ([HabitItem]) -> Void

    init(habits: [HabitItem], persist: @escaping ([HabitItem]) -> Void) {
        self.habits = habits
        self.persist = persist
    }

    func resetDraft() {
        draft = .makeEmpty()
    }

    func upsertDraft() {
        let cleanTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanTitle.isEmpty == false else { return }
        draft.title = cleanTitle

        if let index = habits.firstIndex(where: { $0.id == draft.id }) {
            habits[index] = draft
        } else {
            habits.append(draft)
        }

        persist(habits)
    }

    func delete(at offsets: IndexSet) {
        habits.remove(atOffsets: offsets)
        persist(habits)
    }

    func increment(_ habit: HabitItem, amount: Int = 1) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        let key = Date().yyyymmdd
        let before = habits[index].history[key, default: 0]
        habits[index].history[key, default: 0] += amount
        let after = habits[index].history[key, default: 0]
        if before < habits[index].targetPerDay, after >= habits[index].targetPerDay {
            onHabitCompleted?(habits[index])
        }
        persist(habits)
    }

    func valueToday(for habit: HabitItem) -> Int {
        habit.history[Date().yyyymmdd, default: 0]
    }

    func completedToday(for habit: HabitItem) -> Bool {
        valueToday(for: habit) >= habit.targetPerDay
    }

    func currentStreak(for habit: HabitItem) -> Int {
        var streak = 0
        var day = Calendar.current.startOfDay(for: Date())

        while true {
            let key = day.yyyymmdd
            let value = habit.history[key, default: 0]
            if value >= habit.targetPerDay {
                streak += 1
            } else {
                break
            }
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: day) else {
                break
            }
            day = previous
        }

        return streak
    }

    func weeklyScore(for habit: HabitItem) -> Double {
        let days = Date.last7Days
        let completed = days.filter { day in
            habit.history[day.yyyymmdd, default: 0] >= habit.targetPerDay
        }.count

        return Double(completed) / 7.0
    }

    func weeklyCompletionCount() -> Int {
        habits.reduce(0) { total, habit in
            total + Date.last7Days.filter {
                habit.history[$0.yyyymmdd, default: 0] >= habit.targetPerDay
            }.count
        }
    }

    func heatmapMatrix() -> [[Int]] {
        let days = Date.lastNDays(28)
        let aggregate = days.map { day in
            habits.reduce(0) { partial, habit in
                partial + min(4, habit.history[day.yyyymmdd, default: 0])
            }
        }

        return stride(from: 0, to: aggregate.count, by: 7).map { start in
            Array(aggregate[start..<min(start + 7, aggregate.count)])
        }
    }
}

// =====================================================
// MARK: - Persistence
// [TAG: V2_JSON_STORAGE]
// =====================================================

enum StorageFile: String {
    case tasks = "tasks.json"
    case taskArchive = "task_archive.json"
    case habits = "habits.json"
    case focusLog = "focus_log.json"
    case settings = "settings.json"
    case cloudSyncMeta = "cloud_sync_meta.json"
    case backendTaskSyncMeta = "backend_task_sync_meta.json"
}

final class JSONStorageService {
    private let fm = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        ensureDirectory()
    }

    func load<T: Decodable>(_ type: T.Type, from file: StorageFile, fallback: T) -> T {
        let url = path(for: file)
        guard let data = try? Data(contentsOf: url),
              let object = try? decoder.decode(type, from: data) else {
            return fallback
        }

        return object
    }

    func save<T: Encodable>(_ object: T, to file: StorageFile) {
        let url = path(for: file)
        guard let data = try? encoder.encode(object) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func ensureDirectory() {
        let dir = Self.baseDirectory
        if fm.fileExists(atPath: dir.path) == false {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func path(for file: StorageFile) -> URL {
        Self.baseDirectory.appendingPathComponent(file.rawValue)
    }

    static var baseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("MaddyV2", isDirectory: true)
    }
}

// =====================================================
// MARK: - Utilities
// [TAG: V2_UTILS]
// =====================================================

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension Date {
    var yyyymmdd: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }

    static var last7Days: [Date] {
        lastNDays(7)
    }

    static func lastNDays(_ count: Int) -> [Date] {
        let calendar = Calendar.current
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: -(count - 1 - offset), to: Date())
        }
    }
}

extension Color {
    init?(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let rgb = Int(cleaned, radix: 16) else { return nil }

        let red = Double((rgb >> 16) & 0xFF) / 255
        let green = Double((rgb >> 8) & 0xFF) / 255
        let blue = Double(rgb & 0xFF) / 255
        self = Color(red: red, green: green, blue: blue)
    }

    var toHex: String {
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.deviceRGB) else {
            return "#FF7A2F"
        }

        let red = Int(rgb.redComponent * 255)
        let green = Int(rgb.greenComponent * 255)
        let blue = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
