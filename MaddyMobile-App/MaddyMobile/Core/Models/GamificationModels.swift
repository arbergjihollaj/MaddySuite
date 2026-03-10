import Foundation

// =====================================================
// MARK: - Gamification Models
// [TAG: MOBILE_GAMIFICATION_MODEL]
// =====================================================

enum SkillCategory: String, Codable, CaseIterable, Identifiable {
    case focus
    case execution
    case routine
    case reliability

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

enum Specialization: String, Codable, CaseIterable, Identifiable {
    case none
    case focusSpecialist
    case executionSpecialist
    case routineSpecialist
    case reliabilitySpecialist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .focusSpecialist: return "Focus Specialist"
        case .executionSpecialist: return "Execution Specialist"
        case .routineSpecialist: return "Routine Specialist"
        case .reliabilitySpecialist: return "Reliability Specialist"
        }
    }

    var summary: String {
        switch self {
        case .none:
            return "No specialization selected"
        case .focusSpecialist:
            return "+10% Focus XP, Focus challenges +5 XP"
        case .executionSpecialist:
            return "Hard tasks +5 XP, combo rewards +5 XP"
        case .routineSpecialist:
            return "Routine XP +10%, habit streak rewards +20%"
        case .reliabilitySpecialist:
            return "Reliability XP +10%, daily completion bonus +10 XP"
        }
    }
}

enum RewardTier: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var xpReward: Int {
        switch self {
        case .small: return 20
        case .medium: return 40
        case .large: return 75
        }
    }
}

enum ChallengeDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    var xpReward: Int {
        switch self {
        case .easy: return 10
        case .medium: return 15
        case .hard: return 25
        }
    }

    var momentumReward: Int {
        switch self {
        case .easy: return 2
        case .medium: return 3
        case .hard: return 4
        }
    }
}

enum ChallengeCadence: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case recovery
    case seasonal

    var id: String { rawValue }
}

enum ChallengeKind: String, Codable, CaseIterable, Identifiable {
    case focusSessions
    case completeTasks
    case completeHabits
    case completeDailyTasks
    case perfectDay
    case dailyPackCompletion
    case weeklyConsistency
    case weeklyFocusVolume
    case seasonalMomentum
    case recoveryWalk
    case recoveryClean
    case recoveryReflect

    var id: String { rawValue }
}

enum RecoveryCategory: String, Codable, CaseIterable, Identifiable {
    case physical
    case cleaning
    case reflection

    var id: String { rawValue }
}

enum DailyTaskPack: String, Codable, CaseIterable, Identifiable {
    case productivity
    case routine
    case cleanSpace
    case reset
    case student
    case discipline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .productivity: return "Productivity Pack"
        case .routine: return "Routine Pack"
        case .cleanSpace: return "Clean Space Pack"
        case .reset: return "Reset Pack"
        case .student: return "Student Pack"
        case .discipline: return "Discipline Pack"
        }
    }

    var tag: String {
        "pack:\(rawValue)"
    }
}

struct SkillProgress: Codable, Equatable {
    var xp: Int

    init(xp: Int = 0) {
        self.xp = max(0, xp)
    }

    var level: Int {
        Self.level(forXP: xp)
    }

    var xpInLevel: Int {
        let levelXP = Self.totalXPRequired(toReach: level)
        return max(0, xp - levelXP)
    }

    var xpToNextLevel: Int {
        max(1, Self.xpNeededForNextLevel(level: level))
    }

    var progress0to1: Double {
        let needed = Double(xpToNextLevel)
        guard needed > 0 else { return 0 }
        return min(1.0, Double(xpInLevel) / needed)
    }

    static func xpNeededForNextLevel(level: Int) -> Int {
        let safe = max(1, level)
        let step = safe - 1
        return 50 + (step * 20) + (step * step * 3)
    }

    static func totalXPRequired(toReach targetLevel: Int) -> Int {
        let capped = max(1, targetLevel)
        guard capped > 1 else { return 0 }
        var total = 0
        for level in 1..<capped {
            total += xpNeededForNextLevel(level: level)
        }
        return total
    }

    static func level(forXP xp: Int) -> Int {
        let safe = max(0, xp)
        var level = 1
        var accumulated = 0

        while true {
            let nextCost = xpNeededForNextLevel(level: level)
            if accumulated + nextCost > safe {
                return level
            }
            accumulated += nextCost
            level += 1
            if level > 300 {
                return level
            }
        }
    }
}

struct SkillValues: Codable, Equatable {
    var focus: SkillProgress
    var execution: SkillProgress
    var routine: SkillProgress
    var reliability: SkillProgress

    static let zero = SkillValues(
        focus: SkillProgress(),
        execution: SkillProgress(),
        routine: SkillProgress(),
        reliability: SkillProgress()
    )

    subscript(category: SkillCategory) -> SkillProgress {
        get {
            switch category {
            case .focus: return focus
            case .execution: return execution
            case .routine: return routine
            case .reliability: return reliability
            }
        }
        set {
            switch category {
            case .focus: focus = newValue
            case .execution: execution = newValue
            case .routine: routine = newValue
            case .reliability: reliability = newValue
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case focus
        case execution
        case routine
        case reliability

        // Legacy keys from older builds.
        case discipline
        case planning
        case consistency
        case health
        case learning
        case creativity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let focusProgress = try c.decodeIfPresent(SkillProgress.self, forKey: .focus) ?? SkillProgress()
        let executionProgress = try c.decodeIfPresent(SkillProgress.self, forKey: .execution)
        let routineProgress = try c.decodeIfPresent(SkillProgress.self, forKey: .routine)
        let reliabilityProgress = try c.decodeIfPresent(SkillProgress.self, forKey: .reliability)

        if let executionProgress, let routineProgress, let reliabilityProgress {
            focus = focusProgress
            execution = executionProgress
            routine = routineProgress
            reliability = reliabilityProgress
            return
        }

        let discipline = (try c.decodeIfPresent(SkillProgress.self, forKey: .discipline)?.xp) ?? 0
        let planning = (try c.decodeIfPresent(SkillProgress.self, forKey: .planning)?.xp) ?? 0
        let consistency = (try c.decodeIfPresent(SkillProgress.self, forKey: .consistency)?.xp) ?? 0
        let health = (try c.decodeIfPresent(SkillProgress.self, forKey: .health)?.xp) ?? 0
        let learning = (try c.decodeIfPresent(SkillProgress.self, forKey: .learning)?.xp) ?? 0
        let creativity = (try c.decodeIfPresent(SkillProgress.self, forKey: .creativity)?.xp) ?? 0

        focus = focusProgress
        execution = SkillProgress(xp: max(0, discipline + planning + (creativity / 2)))
        routine = SkillProgress(xp: max(0, consistency + (health / 2)))
        reliability = SkillProgress(xp: max(0, (consistency / 2) + (planning / 2) + (learning / 2)))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(focus, forKey: .focus)
        try c.encode(execution, forKey: .execution)
        try c.encode(routine, forKey: .routine)
        try c.encode(reliability, forKey: .reliability)
    }

    init(
        focus: SkillProgress,
        execution: SkillProgress,
        routine: SkillProgress,
        reliability: SkillProgress
    ) {
        self.focus = focus
        self.execution = execution
        self.routine = routine
        self.reliability = reliability
    }
}

struct DailyChallenge: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var detail: String
    var cadence: ChallengeCadence
    var kind: ChallengeKind
    var difficulty: ChallengeDifficulty
    var target: Int
    var progress: Int
    var rewardXP: Int
    var rewardMomentum: Int
    var completed: Bool
    var rewarded: Bool
    var dayKey: String
}

struct RecoveryChallenge: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var detail: String
    var category: RecoveryCategory
    var severity: Int
    var completed: Bool
    var expiresAt: Date
    var sourceTaskID: UUID?
}

struct PendingRecoveryState: Codable, Equatable {
    var dayKey: String
    var missedCount: Int
    var createdAt: Date
}

struct ResetDayChallengeState: Codable, Equatable {
    var isActive: Bool
    var weekKey: String
    var focusTarget: Int
    var taskTarget: Int
    var habitTarget: Int
    var focusProgress: Int
    var taskProgress: Int
    var habitProgress: Int

    var isCompleted: Bool {
        focusProgress >= focusTarget && taskProgress >= taskTarget && habitProgress >= habitTarget
    }

    static func empty(weekKey: String) -> ResetDayChallengeState {
        ResetDayChallengeState(
            isActive: false,
            weekKey: weekKey,
            focusTarget: 2,
            taskTarget: 2,
            habitTarget: 1,
            focusProgress: 0,
            taskProgress: 0,
            habitProgress: 0
        )
    }
}

struct WeeklyGoalState: Codable, Equatable {
    var weekKey: String
    var requiredDailyCompletions: Int
    var completedDailyCompletions: Int
    var completed: Bool
}

struct SeasonStats: Codable, Equatable {
    var focusSessions: Int
    var tasksDone: Int
    var habitsDone: Int
    var perfectDays: Int

    static let zero = SeasonStats(focusSessions: 0, tasksDone: 0, habitsDone: 0, perfectDays: 0)
}

struct SeasonState: Codable, Equatable {
    var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var seasonalXP: Int
    var badgeUnlocked: Bool
    var unlockedTitles: [String]
    var unlockedPacks: [DailyTaskPack]
    var stats: SeasonStats

    init(
        id: UUID,
        title: String,
        startDate: Date,
        endDate: Date,
        seasonalXP: Int,
        badgeUnlocked: Bool,
        unlockedTitles: [String] = [],
        unlockedPacks: [DailyTaskPack] = [],
        stats: SeasonStats = .zero
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.seasonalXP = seasonalXP
        self.badgeUnlocked = badgeUnlocked
        self.unlockedTitles = unlockedTitles
        self.unlockedPacks = unlockedPacks
        self.stats = stats
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startDate
        case endDate
        case seasonalXP
        case badgeUnlocked
        case unlockedTitles
        case unlockedPacks
        case stats
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Season"
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate) ?? Date()
        endDate = try c.decodeIfPresent(Date.self, forKey: .endDate) ?? Date()
        seasonalXP = try c.decodeIfPresent(Int.self, forKey: .seasonalXP) ?? 0
        badgeUnlocked = try c.decodeIfPresent(Bool.self, forKey: .badgeUnlocked) ?? false
        unlockedTitles = try c.decodeIfPresent([String].self, forKey: .unlockedTitles) ?? []
        unlockedPacks = try c.decodeIfPresent([DailyTaskPack].self, forKey: .unlockedPacks) ?? []
        stats = try c.decodeIfPresent(SeasonStats.self, forKey: .stats) ?? .zero
    }
}

struct SpecializationState: Codable, Equatable {
    var selection: Specialization
    var lastChangedAt: Date?
}
