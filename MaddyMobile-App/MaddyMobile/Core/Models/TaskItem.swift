import Foundation

// =====================================================
// MARK: - Task Models
// [TAG: MOBILE_TASK_MODEL]
// =====================================================

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case backlog
    case inProgress
    case done
    case missed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backlog: return "Backlog"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        case .missed: return "Missed"
        }
    }
}

enum TaskDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var xpReward: Int {
        switch self {
        case .easy: return 8
        case .medium: return 12
        case .hard: return 18
        }
    }
}

enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var xpBonus: Int {
        switch self {
        case .low: return 0
        case .medium: return 2
        case .high: return 4
        }
    }
}

enum TaskSkillTag: String, Codable, CaseIterable, Identifiable {
    case focus
    case execution
    case routine
    case reliability

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

struct TaskItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var dueDate: Date?
    var tags: [String]
    var status: TaskStatus
    var difficulty: TaskDifficulty
    var priority: TaskPriority
    var mappedSkills: [TaskSkillTag]
    var isDailyTask: Bool
    var isRequiredDailyTask: Bool
    var dailyDateKey: String?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    static func empty() -> TaskItem {
        let now = Date()
        return TaskItem(
            id: UUID(),
            title: "",
            dueDate: nil,
            tags: [],
            status: .backlog,
            difficulty: .medium,
            priority: .medium,
            mappedSkills: [.execution],
            isDailyTask: false,
            isRequiredDailyTask: false,
            dailyDateKey: nil,
            createdAt: now,
            updatedAt: now,
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

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case dueDate
        case tags
        case status
        case difficulty
        case priority
        case mappedSkills
        case isDailyTask
        case isRequiredDailyTask
        case dailyDateKey
        case createdAt
        case updatedAt
        case completedAt
    }

    init(
        id: UUID,
        title: String,
        dueDate: Date?,
        tags: [String],
        status: TaskStatus,
        difficulty: TaskDifficulty,
        priority: TaskPriority,
        mappedSkills: [TaskSkillTag],
        isDailyTask: Bool,
        isRequiredDailyTask: Bool,
        dailyDateKey: String?,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.tags = tags
        self.status = status
        self.difficulty = difficulty
        self.priority = priority
        self.mappedSkills = mappedSkills
        self.isDailyTask = isDailyTask
        self.isRequiredDailyTask = isRequiredDailyTask
        self.dailyDateKey = dailyDateKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        status = try c.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .backlog
        difficulty = try c.decodeIfPresent(TaskDifficulty.self, forKey: .difficulty) ?? .medium
        priority = try c.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .medium
        mappedSkills = try c.decodeIfPresent([TaskSkillTag].self, forKey: .mappedSkills) ?? [.execution]
        isDailyTask = try c.decodeIfPresent(Bool.self, forKey: .isDailyTask) ?? false
        isRequiredDailyTask = try c.decodeIfPresent(Bool.self, forKey: .isRequiredDailyTask) ?? false
        dailyDateKey = try c.decodeIfPresent(String.self, forKey: .dailyDateKey)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

struct ArchivedTaskItem: Identifiable, Codable, Equatable {
    var id: UUID
    var task: TaskItem
    var archivedAt: Date
}

// =====================================================
// MARK: - Daily Task Library
// [TAG: MOBILE_DAILY_TASK_LIBRARY]
// =====================================================

struct DailyTaskLibraryItem: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var subtitle: String?
    var pack: DailyTaskPack
    var difficulty: TaskDifficulty
    var preferredSkills: [TaskSkillTag]
    var requiredByDefault: Bool
    var systemGenerated: Bool
    var tags: [String]

    func makeTask(dayKey: String, date: Date, requiredOverride: Bool? = nil, extraTags: [String] = []) -> TaskItem {
        let mergedTags = Array(Set(["daily", "pack", pack.tag] + tags + extraTags)).sorted()
        return TaskItem(
            id: UUID(),
            title: title,
            dueDate: nil,
            tags: mergedTags,
            status: .backlog,
            difficulty: difficulty,
            priority: .medium,
            mappedSkills: preferredSkills.isEmpty ? [.reliability] : Array(preferredSkills.prefix(2)),
            isDailyTask: true,
            isRequiredDailyTask: requiredOverride ?? requiredByDefault,
            dailyDateKey: dayKey,
            createdAt: date,
            updatedAt: date,
            completedAt: nil
        )
    }
}

enum DailyTaskLibrary {
    static let items: [DailyTaskLibraryItem] = [
        // Productivity Pack
        .init(id: "prod_important_morning", title: "Complete 1 important task before 12:00", subtitle: "Prioritize impact early in the day.", pack: .productivity, difficulty: .medium, preferredSkills: [.execution, .reliability], requiredByDefault: true, systemGenerated: true, tags: ["important", "morning", "execution-balance"]),
        .init(id: "prod_two_medium", title: "Finish 2 medium tasks", subtitle: "Convert planning into shipped output.", pack: .productivity, difficulty: .medium, preferredSkills: [.execution], requiredByDefault: true, systemGenerated: true, tags: ["throughput", "execution-balance"]),
        .init(id: "prod_backlog_three", title: "Clear 3 small backlog items", subtitle: "Reduce carry-over and keep your board clean.", pack: .productivity, difficulty: .easy, preferredSkills: [.execution, .reliability], requiredByDefault: false, systemGenerated: true, tags: ["backlog", "cleanup"]),
        .init(id: "prod_avoidance_task", title: "Do 1 task you have been avoiding", subtitle: "Pick the one you've postponed the longest.", pack: .productivity, difficulty: .hard, preferredSkills: [.execution, .focus], requiredByDefault: false, systemGenerated: true, tags: ["avoidance", "courage"]),
        .init(id: "prod_priority_reset", title: "Do a short reset and review priorities", subtitle: "Spend 10 minutes re-ordering your top tasks.", pack: .productivity, difficulty: .easy, preferredSkills: [.reliability], requiredByDefault: false, systemGenerated: true, tags: ["planning", "reset"]),

        // Routine Pack
        .init(id: "routine_required_habits", title: "Complete all required habits today", subtitle: "No required habit misses for the day.", pack: .routine, difficulty: .medium, preferredSkills: [.routine, .reliability], requiredByDefault: true, systemGenerated: true, tags: ["habit", "consistency", "routine-recovery"]),
        .init(id: "routine_morning_anchor", title: "Finish your morning routine before lunch", subtitle: "Lock in your baseline routine early.", pack: .routine, difficulty: .medium, preferredSkills: [.routine], requiredByDefault: true, systemGenerated: true, tags: ["morning", "habit"]),
        .init(id: "routine_evening_reset", title: "Complete your evening reset routine", subtitle: "Close the day with a clean handoff for tomorrow.", pack: .routine, difficulty: .easy, preferredSkills: [.routine, .reliability], requiredByDefault: false, systemGenerated: true, tags: ["evening", "routine-recovery"]),
        .init(id: "routine_habit_streak", title: "Advance one habit streak today", subtitle: "Complete at least one habit currently on a streak.", pack: .routine, difficulty: .easy, preferredSkills: [.routine], requiredByDefault: false, systemGenerated: true, tags: ["streak", "habit"]),

        // Clean Space Pack
        .init(id: "clean_desk_ten", title: "Spend 10 minutes organizing your desk", subtitle: "Remove clutter and reset your work surface.", pack: .cleanSpace, difficulty: .easy, preferredSkills: [.routine], requiredByDefault: false, systemGenerated: true, tags: ["environment", "cleanup"]),
        .init(id: "clean_inbox_zero", title: "Clear your top 10 inbox items", subtitle: "Email/messages/notes count.", pack: .cleanSpace, difficulty: .medium, preferredSkills: [.execution], requiredByDefault: false, systemGenerated: true, tags: ["digital", "cleanup"]),
        .init(id: "clean_workspace_reset", title: "Reset one digital workspace", subtitle: "Files, desktop, or project folders.", pack: .cleanSpace, difficulty: .easy, preferredSkills: [.reliability], requiredByDefault: false, systemGenerated: true, tags: ["digital", "reset"]),
        .init(id: "clean_quick_declutter", title: "Do a 5-minute quick declutter sprint", subtitle: "Set a timer and clean one area only.", pack: .cleanSpace, difficulty: .easy, preferredSkills: [.routine], requiredByDefault: false, systemGenerated: true, tags: ["physical", "recovery-reset"]),

        // Reset Pack
        .init(id: "reset_focus_25", title: "Do 1 focused 25-minute session", subtitle: "Single deep block with no context switching.", pack: .reset, difficulty: .medium, preferredSkills: [.focus], requiredByDefault: true, systemGenerated: true, tags: ["focus-gap", "recovery-reset"]),
        .init(id: "reset_focus_goal", title: "Reach your focus goal today", subtitle: "Hit your current daily focus target.", pack: .reset, difficulty: .hard, preferredSkills: [.focus, .reliability], requiredByDefault: false, systemGenerated: true, tags: ["focus-gap", "goal"]),
        .init(id: "reset_one_finish", title: "Finish 1 task start-to-finish in one sitting", subtitle: "No task hopping during this one.", pack: .reset, difficulty: .medium, preferredSkills: [.focus, .execution], requiredByDefault: false, systemGenerated: true, tags: ["execution-balance", "recovery-reset"]),
        .init(id: "reset_reliability_task", title: "Complete a task mapped to Reliability", subtitle: "Choose a consistency-heavy task.", pack: .reset, difficulty: .easy, preferredSkills: [.reliability], requiredByDefault: false, systemGenerated: true, tags: ["reliability-rebuild"]),

        // Student Pack
        .init(id: "student_study_block", title: "Complete one focused study block", subtitle: "25-45 minutes of uninterrupted study.", pack: .student, difficulty: .medium, preferredSkills: [.focus], requiredByDefault: true, systemGenerated: true, tags: ["study", "focus-gap"]),
        .init(id: "student_summary", title: "Write a short summary of one concept", subtitle: "5-8 bullet points is enough.", pack: .student, difficulty: .medium, preferredSkills: [.execution], requiredByDefault: false, systemGenerated: true, tags: ["study", "execution-balance"]),
        .init(id: "student_review_notes", title: "Review and clean up your notes for 15 minutes", subtitle: "Organize, rename, and mark action points.", pack: .student, difficulty: .easy, preferredSkills: [.routine], requiredByDefault: false, systemGenerated: true, tags: ["study", "cleanup"]),
        .init(id: "student_assignment_push", title: "Make visible progress on one assignment", subtitle: "Complete one concrete sub-step.", pack: .student, difficulty: .hard, preferredSkills: [.execution, .reliability], requiredByDefault: false, systemGenerated: true, tags: ["study", "important"]),

        // Discipline Pack
        .init(id: "discipline_daily_complete", title: "Complete all daily tasks today", subtitle: "Finish the whole daily set.", pack: .discipline, difficulty: .hard, preferredSkills: [.reliability], requiredByDefault: true, systemGenerated: true, tags: ["consistency", "reliability-rebuild"]),
        .init(id: "discipline_no_overdue", title: "Resolve 1 overdue task", subtitle: "Bring one overdue item back to done.", pack: .discipline, difficulty: .medium, preferredSkills: [.reliability, .execution], requiredByDefault: false, systemGenerated: true, tags: ["overdue", "reliability-rebuild"]),
        .init(id: "discipline_three_done", title: "Complete 3 tasks with clean handoff notes", subtitle: "Keep your progress verifiable.", pack: .discipline, difficulty: .hard, preferredSkills: [.execution, .reliability], requiredByDefault: false, systemGenerated: true, tags: ["consistency", "execution-balance"]),
        .init(id: "discipline_follow_plan", title: "Stick to your top 3 priorities for the day", subtitle: "No extra commitments until those are done.", pack: .discipline, difficulty: .medium, preferredSkills: [.reliability], requiredByDefault: false, systemGenerated: true, tags: ["planning", "reliability-rebuild"])
    ]

    static func tasks(
        pack: DailyTaskPack? = nil,
        count: Int,
        dayKey: String,
        date: Date,
        excludingTitles: Set<String> = [],
        matchingAnyTags: [String] = []
    ) -> [TaskItem] {
        let normalizedExclusions = Set(excludingTitles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let loweredTags = Set(matchingAnyTags.map { $0.lowercased() })

        let pool = items.filter { item in
            if let pack, item.pack != pack { return false }
            if normalizedExclusions.contains(item.title.lowercased()) { return false }
            if loweredTags.isEmpty { return true }
            return item.tags.contains { loweredTags.contains($0.lowercased()) }
        }

        let selected = Array(pool.shuffled().prefix(max(0, count)))
        return selected.map { $0.makeTask(dayKey: dayKey, date: date) }
    }
}
