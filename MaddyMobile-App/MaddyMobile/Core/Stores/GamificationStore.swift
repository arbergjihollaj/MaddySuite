import Foundation

// =====================================================
// MARK: - Game Domain
// [TAG: MOBILE_GAME_DOMAIN]
// =====================================================

struct GameState: Codable, Equatable {
    var totalXP: Int
    var level: Int
    var momentum: Int
    var skills: SkillValues

    var dailyChallenges: [DailyChallenge]
    var weeklyChallenges: [DailyChallenge]
    var seasonalChallenges: [DailyChallenge]
    var recoveryChallenge: RecoveryChallenge?
    var pendingRecovery: PendingRecoveryState?

    var weeklyGoal: WeeklyGoalState
    var specialization: SpecializationState
    var season: SeasonState

    var achievements: [Achievement]
    var xpEntries: [XPEntry]

    var completedDailyTaskIDs: [UUID]
    var completedNormalTaskIDs: [UUID]
    var completedHabitKeys: [String]
    var completedFocusSessionKeys: [String]
    var perfectDayKeys: [String]

    var rewardedFocusThreeSessionDayKeys: [String]
    var rewardedFocusGoalDayKeys: [String]
    var rewardedComboKeys: [String]
    var rewardedDailyCompletionDayKeys: [String]
    var rewardedDailyPackKeys: [String]
    var rewardedMilestoneKeys: [String]

    var weeklyDailyCompletionDayKeys: [String]
    var weeklyFocusSessions: Int
    var weeklyTaskCompletions: Int
    var weeklyHabitCompletions: Int
    var weeklyPerfectDays: Int

    var lifetimeFocusSessions: Int
    var lifetimeTaskCompletions: Int
    var lifetimeHabitCompletions: Int
    var lifetimeRequiredHabitCompletions: Int
    var lifetimeDailyCompletionDays: Int

    var badDayStreak: Int
    var resetDayUsedWeekKey: String?
    var resetDayChallenge: ResetDayChallengeState

    var weeklyXPBonusUntil: Date?
    var weeklyXPBonusMultiplier: Double

    var overduePenaltyByDay: [String: Int]

    var lastEvaluatedDayKey: String?
    var lastSummaryDayKey: String?
    var lastModifiedAt: Date

    static func empty(now: Date) -> GameState {
        let dayKey = Self.dayKey(now)
        let weekKey = Self.weekKey(now)
        let season = SeasonEngine.currentSeason(now: now)

        return GameState(
            totalXP: 0,
            level: 1,
            momentum: 50,
            skills: .zero,
            dailyChallenges: ChallengeEngine.generateDailyChallenges(for: dayKey, state: nil),
            weeklyChallenges: ChallengeEngine.generateWeeklyChallenges(for: weekKey, state: nil),
            seasonalChallenges: ChallengeEngine.generateSeasonalChallenges(for: season),
            recoveryChallenge: nil,
            pendingRecovery: nil,
            weeklyGoal: WeeklyGoalState(weekKey: weekKey, requiredDailyCompletions: 5, completedDailyCompletions: 0, completed: false),
            specialization: SpecializationState(selection: .none, lastChangedAt: nil),
            season: season,
            achievements: [],
            xpEntries: [],
            completedDailyTaskIDs: [],
            completedNormalTaskIDs: [],
            completedHabitKeys: [],
            completedFocusSessionKeys: [],
            perfectDayKeys: [],
            rewardedFocusThreeSessionDayKeys: [],
            rewardedFocusGoalDayKeys: [],
            rewardedComboKeys: [],
            rewardedDailyCompletionDayKeys: [],
            rewardedDailyPackKeys: [],
            rewardedMilestoneKeys: [],
            weeklyDailyCompletionDayKeys: [],
            weeklyFocusSessions: 0,
            weeklyTaskCompletions: 0,
            weeklyHabitCompletions: 0,
            weeklyPerfectDays: 0,
            lifetimeFocusSessions: 0,
            lifetimeTaskCompletions: 0,
            lifetimeHabitCompletions: 0,
            lifetimeRequiredHabitCompletions: 0,
            lifetimeDailyCompletionDays: 0,
            badDayStreak: 0,
            resetDayUsedWeekKey: nil,
            resetDayChallenge: .empty(weekKey: weekKey),
            weeklyXPBonusUntil: nil,
            weeklyXPBonusMultiplier: 1.0,
            overduePenaltyByDay: [:],
            lastEvaluatedDayKey: nil,
            lastSummaryDayKey: nil,
            lastModifiedAt: now
        )
    }

    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func weekKey(_ date: Date) -> String {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(comps.yearForWeekOfYear ?? 0)-W\(comps.weekOfYear ?? 0)"
    }
}

struct RewardDefinition {
    var xp: Int
    var skillXP: [(SkillCategory, Int)]
    var momentum: Int
    var reason: String
}

struct MomentumState {
    var value: Int

    var xpMultiplier: Double {
        switch value {
        case ..<70: return 1.0
        case 70..<90: return 1.05
        default: return 1.08
        }
    }
}

// =====================================================
// MARK: - Event Router
// [TAG: MOBILE_GAMIFICATION_EVENT_ROUTER]
// =====================================================

enum GamificationEvent {
    case focusSessionCompleted(session: FocusSession, sessionsToday: Int, dailyGoalReached: Bool)
    case taskCompleted(task: TaskItem, completedToday: Int)
    case dailyTaskMissed(task: TaskItem)
    case habitCompleted(habit: Habit, isRequired: Bool)
    case dailyChallengeCompleted(id: UUID)
    case weeklyChallengeCompleted(id: UUID)
    case recoveryChallengeCompleted
    case dailyEvaluation(context: DailyEvaluationContext)
    case weeklyGoalCompleted
    case activateResetDay
}

struct DailyEvaluationContext {
    var date: Date
    var dailyTasks: [TaskItem]
    var requiredHabits: [Habit]
    var completedRequiredHabitCount: Int
    var focusGoalReached: Bool
    var completedNormalTaskCount: Int
}

struct GamificationEventRouter {
    static func route(_ event: GamificationEvent, to handler: (GamificationEvent) -> Void) {
        handler(event)
    }
}

// =====================================================
// MARK: - Engines
// [TAG: MOBILE_GAMIFICATION_ENGINES]
// =====================================================

struct ProgressionEngine {
    static func level(forXP xp: Int) -> Int {
        let safeXP = max(0, xp)
        var level = 1
        var consumed = 0

        while true {
            let needed = xpNeededForNextLevel(level: level)
            if consumed + needed > safeXP {
                return level
            }
            consumed += needed
            level += 1
            if level > 1000 { return level }
        }
    }

    static func xpNeededForNextLevel(level: Int) -> Int {
        let l = max(1, level)
        let step = l - 1
        return 100 + (step * 35) + (step * step * 5)
    }
}

struct DailyLoopEngine {
    static func shouldRunDayEvaluation(now: Date) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        return hour == 20 && minute <= 2
    }
}

struct MomentumEngine {
    static func apply(_ delta: Int, to current: Int) -> Int {
        min(100, max(0, current + delta))
    }
}

struct TaskEvaluationEngine {
    static func baseXP(task: TaskItem) -> Int {
        task.difficulty.xpReward + task.priority.xpBonus
    }

    static func splitSkillXP(baseXP: Int, mapped: [TaskSkillTag]) -> [(TaskSkillTag, Int)] {
        let chosen = mapped.isEmpty ? [.execution] : Array(mapped.prefix(2))
        guard chosen.count > 1 else {
            return [(chosen[0], baseXP)]
        }

        let primary = baseXP / 2
        let secondary = baseXP - primary
        return [(chosen[0], max(1, primary)), (chosen[1], max(1, secondary))]
    }

    static func isOverdueCompletion(_ task: TaskItem) -> Bool {
        guard let due = task.dueDate else { return false }
        let completedAt = task.completedAt ?? Date()
        return completedAt > due
    }
}

struct HabitEvaluationEngine {
    static func isRequired(_ habit: Habit) -> Bool {
        let normalized = habit.title.lowercased()
        return normalized.contains("required") || normalized.contains("must")
    }

    static func weightXP(for habit: Habit) -> Int {
        switch habit.targetValue {
        case ..<2: return 6
        case 2...4: return 10
        default: return 14
        }
    }
}

struct FocusEvaluationEngine {
    static func isAborted(_ session: FocusSession) -> Bool {
        session.durationMinutes <= 0
    }
}

struct ChallengeEngine {
    static func generateDailyChallenges(for dayKey: String, state: GameState?) -> [DailyChallenge] {
        let lowReliability = (state?.skills.reliability.level ?? 1) < 5
        let highFocus = (state?.skills.focus.level ?? 1) > ((state?.skills.execution.level ?? 1) + 1)

        let first = DailyChallenge(
            id: UUID(),
            title: highFocus ? "Execution Alignment" : "Focus Sprint",
            detail: highFocus ? "Complete 3 normal tasks today" : "Complete 2 focus sessions today",
            cadence: .daily,
            kind: highFocus ? .completeTasks : .focusSessions,
            difficulty: .medium,
            target: highFocus ? 3 : 2,
            progress: 0,
            rewardXP: highFocus ? 15 : 20,
            rewardMomentum: 4,
            completed: false,
            rewarded: false,
            dayKey: dayKey
        )

        let second = DailyChallenge(
            id: UUID(),
            title: lowReliability ? "Reliability Stabilizer" : "Routine Anchor",
            detail: lowReliability ? "Complete all daily tasks" : "Complete 2 habits",
            cadence: .daily,
            kind: lowReliability ? .completeDailyTasks : .completeHabits,
            difficulty: lowReliability ? .hard : .easy,
            target: lowReliability ? 3 : 2,
            progress: 0,
            rewardXP: lowReliability ? 25 : 10,
            rewardMomentum: lowReliability ? 4 : 2,
            completed: false,
            rewarded: false,
            dayKey: dayKey
        )

        let third = DailyChallenge(
            id: UUID(),
            title: "Pack Finisher",
            detail: "Finish one daily task pack",
            cadence: .daily,
            kind: .dailyPackCompletion,
            difficulty: .medium,
            target: 1,
            progress: 0,
            rewardXP: 15,
            rewardMomentum: 3,
            completed: false,
            rewarded: false,
            dayKey: dayKey
        )

        return [first, second, third]
    }

    static func generateWeeklyChallenges(for weekKey: String, state: GameState?) -> [DailyChallenge] {
        let medium = DailyChallenge(
            id: UUID(),
            title: "Reliability Week",
            detail: "Complete daily tasks on 5 days",
            cadence: .weekly,
            kind: .weeklyConsistency,
            difficulty: .medium,
            target: 5,
            progress: 0,
            rewardXP: 30,
            rewardMomentum: 5,
            completed: false,
            rewarded: false,
            dayKey: weekKey
        )

        let hardFocusTarget = max(8, min(14, (state?.weeklyFocusSessions ?? 0) + 8))
        let hard = DailyChallenge(
            id: UUID(),
            title: "Focus Volume",
            detail: "Complete \(hardFocusTarget) focus sessions this week",
            cadence: .weekly,
            kind: .weeklyFocusVolume,
            difficulty: .hard,
            target: hardFocusTarget,
            progress: 0,
            rewardXP: 55,
            rewardMomentum: 8,
            completed: false,
            rewarded: false,
            dayKey: weekKey
        )

        return [medium, hard]
    }

    static func generateSeasonalChallenges(for season: SeasonState) -> [DailyChallenge] {
        [
            DailyChallenge(
                id: UUID(),
                title: "Season Climb",
                detail: "Reach 25 perfect days this season",
                cadence: .seasonal,
                kind: .seasonalMomentum,
                difficulty: .hard,
                target: 25,
                progress: 0,
                rewardXP: 75,
                rewardMomentum: 8,
                completed: false,
                rewarded: false,
                dayKey: season.id.uuidString
            )
        ]
    }

    static func rewardSkillXP(for challenge: DailyChallenge) -> [(SkillCategory, Int)] {
        switch (challenge.cadence, challenge.kind) {
        case (_, .focusSessions), (.weekly, .weeklyFocusVolume):
            return [(.focus, challenge.cadence == .weekly ? 15 : 10)]
        case (_, .completeTasks):
            return [(.execution, 10)]
        case (_, .completeHabits):
            return [(.routine, 10)]
        case (_, .completeDailyTasks),
             (_, .dailyPackCompletion),
             (_, .perfectDay),
             (_, .weeklyConsistency),
             (_, .seasonalMomentum),
             (_, .weeklyFocusVolume):
            return [(.reliability, 10)]
        case (_, .recoveryWalk), (_, .recoveryClean), (_, .recoveryReflect):
            return [(.reliability, 6)]
        }
    }
}

struct AchievementUnlock {
    var achievement: Achievement
    var xpReward: Int
}

struct AchievementEngine {
    static func computeNewAchievements(state: GameState) -> [AchievementUnlock] {
        let existing = Set(state.achievements.map(\.title))
        var results: [AchievementUnlock] = []

        func append(
            _ title: String,
            detail: String,
            icon: String,
            tier: RewardTier,
            hidden: Bool = false,
            rewardTitle: String? = nil,
            rewardCosmetic: String? = nil
        ) {
            guard existing.contains(title) == false else { return }
            let achievement = Achievement(
                id: UUID(),
                title: title,
                detail: detail,
                icon: icon,
                unlockedAt: Date(),
                tier: tier,
                hidden: hidden,
                rewardTitle: rewardTitle,
                rewardCosmetic: rewardCosmetic
            )
            results.append(AchievementUnlock(achievement: achievement, xpReward: tier.xpReward))
        }

        if state.totalXP >= 100 {
            append("First 100 XP", detail: "Reach your first major progression checkpoint.", icon: "sparkles", tier: .small, rewardTitle: "Starter")
        }
        if state.totalXP >= 1000 {
            append("Level Momentum", detail: "Accumulate 1000 total XP.", icon: "bolt.fill", tier: .medium, rewardCosmetic: "pulse-ring")
        }
        if state.perfectDayKeys.count >= 7 {
            append("Perfect Seven", detail: "Achieve 7 perfect days.", icon: "star.circle.fill", tier: .large, rewardTitle: "Flawless")
        }
        if state.lifetimeFocusSessions >= 30 {
            append("Focus Adept", detail: "Complete 30 focus sessions.", icon: "timer", tier: .medium, rewardTitle: "Session Adept")
        }
        if state.lifetimeTaskCompletions >= 100 {
            append("Execution Centurion", detail: "Complete 100 normal tasks.", icon: "checkmark.seal.fill", tier: .large, rewardCosmetic: "task-halo")
        }
        if state.lifetimeRequiredHabitCompletions >= 30 {
            append("Reliable Core", detail: "Complete 30 required habits.", icon: "shield.lefthalf.filled", tier: .medium, rewardTitle: "Reliable")
        }
        if state.lifetimeDailyCompletionDays >= 14 {
            append("Daily Commander", detail: "Finish all daily tasks on 14 days.", icon: "calendar.badge.checkmark", tier: .large, rewardTitle: "Commander")
        }
        if state.momentum >= 95 {
            append("Hidden: Peak Form", detail: "Reach momentum 95+.", icon: "flame.fill", tier: .small, hidden: true, rewardCosmetic: "ember")
        }

        return results
    }
}

struct RecoveryChallengeManager {
    static func makeChallenge(severity: Int, taskID: UUID?) -> RecoveryChallenge {
        let safe = max(1, min(3, severity))

        switch safe {
        case 1:
            return RecoveryChallenge(
                id: UUID(),
                title: "Recovery Reflection",
                detail: "Write 3 short lines about what blocked you.",
                category: .reflection,
                severity: safe,
                completed: false,
                expiresAt: Date().addingTimeInterval(8 * 60 * 60),
                sourceTaskID: taskID
            )
        case 2:
            return RecoveryChallenge(
                id: UUID(),
                title: "Recovery Reset",
                detail: "Tidy your desk or room for 5 minutes.",
                category: .cleaning,
                severity: safe,
                completed: false,
                expiresAt: Date().addingTimeInterval(8 * 60 * 60),
                sourceTaskID: taskID
            )
        default:
            return RecoveryChallenge(
                id: UUID(),
                title: "Recovery Movement",
                detail: "Take a short walk or complete 20 squats.",
                category: .physical,
                severity: safe,
                completed: false,
                expiresAt: Date().addingTimeInterval(8 * 60 * 60),
                sourceTaskID: taskID
            )
        }
    }
}

struct SmartDailyTaskGenerator {
    static func suggestDailyTaskTemplates(state: GameState) -> [TaskItem] {
        let todayKey = GameState.dayKey(Date())
        let now = Date()
        let pack = preferredPack(for: state)
        var seenTitles = Set<String>()
        var templates = DailyTaskLibrary.tasks(
            pack: pack,
            count: 2,
            dayKey: todayKey,
            date: now
        )
        templates.forEach { seenTitles.insert($0.title.lowercased()) }

        let focusLevel = state.skills.focus.level
        let executionLevel = state.skills.execution.level
        let routineLevel = state.skills.routine.level
        let reliabilityLevel = state.skills.reliability.level

        if focusLevel >= executionLevel + 2 {
            appendFirstAvailable(
                into: &templates,
                seenTitles: &seenTitles,
                candidates: DailyTaskLibrary.tasks(
                    pack: .productivity,
                    count: 2,
                    dayKey: todayKey,
                    date: now,
                    excludingTitles: seenTitles,
                    matchingAnyTags: ["execution-balance", "important"]
                )
            )
        }

        if routineLevel + 1 < reliabilityLevel {
            appendFirstAvailable(
                into: &templates,
                seenTitles: &seenTitles,
                candidates: DailyTaskLibrary.tasks(
                    pack: .routine,
                    count: 2,
                    dayKey: todayKey,
                    date: now,
                    excludingTitles: seenTitles,
                    matchingAnyTags: ["routine-recovery", "habit"]
                )
            )
        }

        if state.momentum < 40 {
            appendFirstAvailable(
                into: &templates,
                seenTitles: &seenTitles,
                candidates: DailyTaskLibrary.tasks(
                    pack: .reset,
                    count: 3,
                    dayKey: todayKey,
                    date: now,
                    excludingTitles: seenTitles,
                    matchingAnyTags: ["recovery-reset", "reliability-rebuild"]
                )
            )
        }

        if state.skills.execution.level >= state.skills.focus.level + 3 {
            appendFirstAvailable(
                into: &templates,
                seenTitles: &seenTitles,
                candidates: DailyTaskLibrary.tasks(
                    pack: .student,
                    count: 2,
                    dayKey: todayKey,
                    date: now,
                    excludingTitles: seenTitles,
                    matchingAnyTags: ["focus-gap", "study"]
                ) + DailyTaskLibrary.tasks(
                    pack: .reset,
                    count: 2,
                    dayKey: todayKey,
                    date: now,
                    excludingTitles: seenTitles,
                    matchingAnyTags: ["focus-gap"]
                )
            )
        }

        if templates.count < 4 {
            let filler = DailyTaskLibrary.tasks(
                pack: pack,
                count: 4 - templates.count,
                dayKey: todayKey,
                date: now,
                excludingTitles: seenTitles
            )
            for task in filler {
                let key = task.title.lowercased()
                guard seenTitles.contains(key) == false else { continue }
                seenTitles.insert(key)
                templates.append(task)
            }
        }

        return templates
    }

    private static func preferredPack(for state: GameState) -> DailyTaskPack {
        if state.skills.reliability.level <= state.skills.execution.level {
            return .discipline
        }
        if state.skills.routine.level < state.skills.focus.level {
            return .routine
        }
        if state.momentum < 45 {
            return .reset
        }
        if state.skills.execution.level >= state.skills.focus.level + 2 {
            return .student
        }
        return .productivity
    }

    private static func appendFirstAvailable(
        into templates: inout [TaskItem],
        seenTitles: inout Set<String>,
        candidates: [TaskItem]
    ) {
        guard let candidate = candidates.first(where: { seenTitles.contains($0.title.lowercased()) == false }) else { return }
        seenTitles.insert(candidate.title.lowercased())
        templates.append(candidate)
    }
}

struct SeasonEngine {
    static func currentSeason(now: Date) -> SeasonState {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: now)
        let year = components.year ?? 2026
        let month = components.month ?? 1

        let seasonStartMonth = ((max(1, month) - 1) / 3) * 3 + 1
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = seasonStartMonth
        startComponents.day = 1

        let startDate = calendar.date(from: startComponents) ?? now
        let endDate = calendar.date(byAdding: .month, value: 3, to: startDate)?.addingTimeInterval(-1) ?? now

        return SeasonState(
            id: UUID(),
            title: "Season \(year).\(seasonStartMonth)",
            startDate: startDate,
            endDate: endDate,
            seasonalXP: 0,
            badgeUnlocked: false,
            unlockedTitles: [],
            unlockedPacks: [.productivity],
            stats: .zero
        )
    }
}

struct RewardPresentationCoordinator {
    static func pushEntry(_ reward: RewardDefinition, into entries: inout [XPEntry], totalXP: Int, level: Int) {
        let entry = XPEntry(
            id: UUID(),
            date: Date(),
            delta: reward.xp,
            totalXP: totalXP,
            level: level,
            reason: reward.reason
        )
        entries.insert(entry, at: 0)
        if entries.count > 240 {
            entries = Array(entries.prefix(240))
        }
    }
}

// =====================================================
// MARK: - Game Store
// [TAG: MOBILE_GAME_STORE]
// =====================================================

@MainActor
final class GamificationStore: ObservableObject {
    struct State: Codable {
        var game: GameState
    }

    struct CloudSnapshot: Codable {
        var game: GameState
        var modifiedAt: Date
    }

    private struct LegacyStateV1: Codable {
        var game: LegacyGameState
    }

    private struct LegacyGameState: Codable {
        var totalXP: Int
        var level: Int
        var momentum: Int
        var skills: SkillValues
        var dailyChallenges: [DailyChallenge]
        var weeklyChallenges: [DailyChallenge]
        var recoveryChallenge: RecoveryChallenge?
        var weeklyGoal: WeeklyGoalState
        var specialization: SpecializationState
        var season: SeasonState
        var achievements: [Achievement]
        var xpEntries: [XPEntry]
        var completedDailyTaskIDs: [UUID]
        var completedNormalTaskIDs: [UUID]
        var completedHabitKeys: [String]
        var completedFocusSessionKeys: [String]
        var perfectDayKeys: [String]
        var badDayStreak: Int
        var resetDayUsedWeekKey: String?
        var weeklyXPBonusUntil: Date?
        var weeklyXPBonusMultiplier: Double
        var lastEvaluatedDayKey: String?
        var lastModifiedAt: Date
    }

    @Published private(set) var totalXP: Int
    @Published private(set) var level: Int
    @Published private(set) var momentum: Int
    @Published private(set) var skills: SkillValues

    @Published private(set) var dailyChallenges: [DailyChallenge]
    @Published private(set) var weeklyChallenges: [DailyChallenge]
    @Published private(set) var seasonalChallenges: [DailyChallenge]
    @Published private(set) var recoveryChallenge: RecoveryChallenge?
    @Published private(set) var achievements: [Achievement]
    @Published private(set) var xpEntries: [XPEntry]

    @Published private(set) var specialization: SpecializationState
    @Published private(set) var season: SeasonState
    @Published private(set) var weeklyGoal: WeeklyGoalState
    @Published private(set) var resetDayChallenge: ResetDayChallengeState

    @Published private(set) var dailySummaryText: String?
    @Published private(set) var dailySummarySignal: Int = 0

    var onDataChanged: (() -> Void)?

    private let storage: LocalJSONStorage
    private let fileName = "gamification.json"
    private(set) var lastModifiedAt: Date
    private var isApplyingCloudSnapshot = false
    private var state: GameState

    init(storage: LocalJSONStorage = .shared) {
        self.storage = storage
        let now = Date()

        let fallback = State(game: .empty(now: now))
        if let persisted = storage.loadIfPresent(State.self, from: fileName) {
            state = persisted.game
        } else if let legacy = storage.loadIfPresent(LegacyStateV1.self, from: fileName) {
            state = Self.migrateLegacy(legacy.game, now: now)
        } else {
            state = fallback.game
        }

        totalXP = state.totalXP
        level = state.level
        momentum = state.momentum
        skills = state.skills
        dailyChallenges = state.dailyChallenges
        weeklyChallenges = state.weeklyChallenges
        seasonalChallenges = state.seasonalChallenges
        recoveryChallenge = state.recoveryChallenge
        achievements = state.achievements
        xpEntries = state.xpEntries
        specialization = state.specialization
        season = state.season
        weeklyGoal = state.weeklyGoal
        resetDayChallenge = state.resetDayChallenge
        lastModifiedAt = state.lastModifiedAt

        ensureDailyState(now: now)
        recalculateDerived()
        persist()
    }

    // =====================================================
    // MARK: - Public API
    // [TAG: MOBILE_GAME_PUBLIC_API]
    // =====================================================

    func registerFocusCompletion(session: FocusSession, sessionsToday: Int, dailyGoalReached: Bool) {
        guard FocusEvaluationEngine.isAborted(session) == false else { return }
        route(.focusSessionCompleted(session: session, sessionsToday: sessionsToday, dailyGoalReached: dailyGoalReached))
    }

    func registerTaskCompletion(task: TaskItem, completedToday: Int) {
        route(.taskCompleted(task: task, completedToday: completedToday))
    }

    func registerMissedDailyTask(_ task: TaskItem) {
        route(.dailyTaskMissed(task: task))
    }

    func registerHabitCompletion(habit: Habit, isRequired: Bool) {
        route(.habitCompleted(habit: habit, isRequired: isRequired))
    }

    func evaluateDay(context: DailyEvaluationContext) {
        route(.dailyEvaluation(context: context))
    }

    func completeRecoveryChallenge() {
        route(.recoveryChallengeCompleted)
    }

    func completeDailyChallenge(id: UUID) {
        route(.dailyChallengeCompleted(id: id))
    }

    func completeWeeklyChallenge(id: UUID) {
        route(.weeklyChallengeCompleted(id: id))
    }

    func activateResetDayIfAvailable() {
        route(.activateResetDay)
    }

    func setSpecialization(_ next: Specialization, at date: Date = Date()) -> Bool {
        guard next != state.specialization.selection else { return false }

        let maxLevel = SkillCategory.allCases.map { state.skills[$0].level }.max() ?? 1
        guard maxLevel >= 10 else { return false }

        if let last = state.specialization.lastChangedAt {
            let months = Calendar.current.dateComponents([.month], from: last, to: date).month ?? 0
            guard months >= 1 else { return false }
        }

        state.specialization = SpecializationState(selection: next, lastChangedAt: date)
        commitMutation(reason: "specialization")
        return true
    }

    func generateSmartDailyTasks() -> [TaskItem] {
        SmartDailyTaskGenerator.suggestDailyTaskTemplates(state: state)
    }

    func cloudSnapshot() -> CloudSnapshot {
        CloudSnapshot(game: state, modifiedAt: state.lastModifiedAt)
    }

    func applyCloudSnapshot(_ snapshot: CloudSnapshot) {
        guard snapshot.modifiedAt > state.lastModifiedAt else { return }

        isApplyingCloudSnapshot = true
        state = snapshot.game
        state.lastModifiedAt = snapshot.modifiedAt
        ensureDailyState(now: Date())
        recalculateDerived()
        isApplyingCloudSnapshot = false
        persist()
    }

    // =====================================================
    // MARK: - Event Routing
    // [TAG: MOBILE_GAMIFICATION_EVENT_ROUTER]
    // =====================================================

    private func route(_ event: GamificationEvent) {
        ensureDailyState(now: Date())
        GamificationEventRouter.route(event) { [weak self] evt in
            self?.handle(event: evt)
        }
    }

    private func handle(event: GamificationEvent) {
        switch event {
        case .focusSessionCompleted(let session, let sessionsToday, let dailyGoalReached):
            applyFocusReward(session: session, sessionsToday: sessionsToday, dailyGoalReached: dailyGoalReached)
        case .taskCompleted(let task, let completedToday):
            applyTaskReward(task: task, completedToday: completedToday)
        case .dailyTaskMissed(let task):
            registerMissedDailyTaskInternal(task: task)
        case .habitCompleted(let habit, let isRequired):
            applyHabitReward(habit: habit, isRequired: isRequired)
        case .dailyChallengeCompleted(let id):
            markChallengeCompleted(id: id, cadence: .daily)
        case .weeklyChallengeCompleted(let id):
            markChallengeCompleted(id: id, cadence: .weekly)
        case .recoveryChallengeCompleted:
            applyRecoveryCompletion()
        case .dailyEvaluation(let context):
            runDailyEvaluation(context: context)
        case .weeklyGoalCompleted:
            applyWeeklyGoalReward()
        case .activateResetDay:
            activateResetDay()
        }

        refreshChallengesAndAchievements()
        commitMutation(reason: "game event")
    }

    // =====================================================
    // MARK: - Reward Logic
    // [TAG: MOBILE_REWARD_LOGIC]
    // =====================================================

    private func applyFocusReward(session: FocusSession, sessionsToday: Int, dailyGoalReached: Bool) {
        let dayKey = GameState.dayKey(session.startDate)
        let sessionKey = "\(session.id.uuidString)-\(dayKey)"
        guard state.completedFocusSessionKeys.contains(sessionKey) == false else { return }

        state.completedFocusSessionKeys.append(sessionKey)
        state.lifetimeFocusSessions += 1
        state.weeklyFocusSessions += 1
        state.season.stats.focusSessions += 1

        award(RewardDefinition(
            xp: 10,
            skillXP: [(.focus, 10)],
            momentum: 1,
            reason: "Focus session completed"
        ))

        if sessionsToday == 3 {
            let bonusKey = "\(dayKey)-focus3"
            if state.rewardedFocusThreeSessionDayKeys.contains(bonusKey) == false {
                state.rewardedFocusThreeSessionDayKeys.append(bonusKey)
                award(RewardDefinition(
                    xp: 10,
                    skillXP: [(.focus, 5)],
                    momentum: 3,
                    reason: "3 focus sessions in one day"
                ))
            }
        }

        if dailyGoalReached {
            let goalKey = "\(dayKey)-focusgoal"
            if state.rewardedFocusGoalDayKeys.contains(goalKey) == false {
                state.rewardedFocusGoalDayKeys.append(goalKey)
                award(RewardDefinition(
                    xp: 15,
                    skillXP: [(.focus, 8)],
                    momentum: 4,
                    reason: "Focus daily goal reached"
                ))
            }
        }

        trackResetProgress(focusDelta: 1, taskDelta: 0, habitDelta: 0)
    }

    private func applyTaskReward(task: TaskItem, completedToday: Int) {
        let dayKey = GameState.dayKey(task.completedAt ?? Date())

        if task.isDailyTask {
            guard state.completedDailyTaskIDs.contains(task.id) == false else { return }
            state.completedDailyTaskIDs.append(task.id)
            applyDailyTaskReward(task: task)
            trackResetProgress(focusDelta: 0, taskDelta: 1, habitDelta: 0)
            return
        }

        guard state.completedNormalTaskIDs.contains(task.id) == false else { return }
        state.completedNormalTaskIDs.append(task.id)
        state.lifetimeTaskCompletions += 1
        state.weeklyTaskCompletions += 1
        state.season.stats.tasksDone += 1

        var xp = TaskEvaluationEngine.baseXP(task: task)
        if task.difficulty == .hard, state.specialization.selection == .executionSpecialist {
            xp += 5
        }

        let mappedAwards = TaskEvaluationEngine
            .splitSkillXP(baseXP: xp, mapped: task.mappedSkills)
            .map { (mapSkill($0.0), $0.1) }

        award(RewardDefinition(
            xp: xp,
            skillXP: mappedAwards,
            momentum: 0,
            reason: "Task completed"
        ))

        awardComboIfNeeded(dayKey: dayKey, completedToday: completedToday)

        if TaskEvaluationEngine.isOverdueCompletion(task) {
            let current = state.overduePenaltyByDay[dayKey, default: 0]
            if current > -9 {
                state.overduePenaltyByDay[dayKey] = max(-9, current - 3)
                applySkillOnly(.reliability, delta: -3)
            }
        }

        trackResetProgress(focusDelta: 0, taskDelta: 1, habitDelta: 0)
    }

    private func applyDailyTaskReward(task: TaskItem) {
        var skillAwards: [(SkillCategory, Int)] = [(.reliability, 10)]
        let mapped = task.mappedSkills.isEmpty ? [TaskSkillTag.reliability] : Array(task.mappedSkills.prefix(2))

        if mapped.count == 1 {
            skillAwards.append((mapSkill(mapped[0]), 6))
        } else {
            skillAwards.append((mapSkill(mapped[0]), 3))
            skillAwards.append((mapSkill(mapped[1]), 3))
        }

        award(RewardDefinition(
            xp: 20,
            skillXP: skillAwards,
            momentum: 2,
            reason: "Daily task completed"
        ))
    }

    private func applyHabitReward(habit: Habit, isRequired: Bool) {
        let dayKey = GameState.dayKey(Date())
        let uniqueKey = "\(habit.id.uuidString)-\(dayKey)"
        guard state.completedHabitKeys.contains(uniqueKey) == false else { return }

        state.completedHabitKeys.append(uniqueKey)
        state.lifetimeHabitCompletions += 1
        state.weeklyHabitCompletions += 1
        state.season.stats.habitsDone += 1

        let weightXP = HabitEvaluationEngine.weightXP(for: habit)
        var skillAwards: [(SkillCategory, Int)] = [(.routine, weightXP)]

        if isRequired {
            skillAwards.append((.reliability, 2))
            state.lifetimeRequiredHabitCompletions += 1
        }

        award(RewardDefinition(
            xp: weightXP,
            skillXP: skillAwards,
            momentum: 0,
            reason: "Habit completed"
        ))

        let streakBonus = streakReward(for: habit.streak)
        if streakBonus > 0 {
            award(RewardDefinition(
                xp: streakBonus,
                skillXP: [],
                momentum: 0,
                reason: "Habit streak reward"
            ))
        }

        trackResetProgress(focusDelta: 0, taskDelta: 0, habitDelta: 1)
    }

    private func registerMissedDailyTaskInternal(task: TaskItem) {
        let dayKey = task.effectiveDailyKey
        let nextCount: Int

        if let pending = state.pendingRecovery, pending.dayKey == dayKey {
            nextCount = pending.missedCount + 1
        } else {
            nextCount = 1
        }

        state.pendingRecovery = PendingRecoveryState(
            dayKey: dayKey,
            missedCount: min(6, nextCount),
            createdAt: Date()
        )

        state.recoveryChallenge = RecoveryChallengeManager.makeChallenge(
            severity: min(3, max(1, nextCount)),
            taskID: task.id
        )
    }

    private func runDailyEvaluation(context: DailyEvaluationContext) {
        let dayKey = GameState.dayKey(context.date)
        guard state.lastEvaluatedDayKey != dayKey else { return }
        state.lastEvaluatedDayKey = dayKey

        settlePendingRecoveryIfNeeded(evaluatingDayKey: dayKey)

        let dailyTasks = context.dailyTasks
        let missedDailyCount = dailyTasks.filter { $0.status != .done }.count

        if missedDailyCount > 0 {
            state.pendingRecovery = PendingRecoveryState(dayKey: dayKey, missedCount: missedDailyCount, createdAt: Date())
            state.recoveryChallenge = RecoveryChallengeManager.makeChallenge(severity: min(3, missedDailyCount), taskID: nil)
        }

        if context.focusGoalReached == false {
            state.momentum = MomentumEngine.apply(-4, to: state.momentum)
        }

        if context.completedRequiredHabitCount < context.requiredHabits.count {
            state.momentum = MomentumEngine.apply(-3, to: state.momentum)
        }

        let allDailyDone = dailyTasks.isEmpty == false && dailyTasks.allSatisfy { $0.status == .done }
        if allDailyDone {
            rewardAllDailyCompletion(dayKey: dayKey)
            rewardCompletedDailyPacks(dayKey: dayKey, dailyTasks: dailyTasks)
        }

        let majorMisses = missedDailyCount > 0
        let perfectDay = allDailyDone &&
            context.focusGoalReached &&
            context.completedNormalTaskCount >= 1 &&
            context.completedRequiredHabitCount >= context.requiredHabits.count &&
            majorMisses == false

        if perfectDay && state.perfectDayKeys.contains(dayKey) == false {
            state.perfectDayKeys.append(dayKey)
            state.weeklyPerfectDays += 1
            state.season.stats.perfectDays += 1
            award(RewardDefinition(
                xp: 30,
                skillXP: [(.reliability, 5)],
                momentum: 10,
                reason: "Perfect day"
            ))
            state.badDayStreak = 0
        } else if majorMisses || context.focusGoalReached == false || context.completedRequiredHabitCount < context.requiredHabits.count {
            state.badDayStreak = min(7, state.badDayStreak + 1)
        }

        if state.weeklyGoal.completed == false,
           state.weeklyGoal.completedDailyCompletions >= state.weeklyGoal.requiredDailyCompletions {
            applyWeeklyGoalReward()
        }

        dailySummaryText = makeDailySummary(
            dayKey: dayKey,
            allDailyDone: allDailyDone,
            missedDailyCount: missedDailyCount,
            perfectDay: perfectDay,
            focusGoalReached: context.focusGoalReached,
            requiredHabitsDone: context.completedRequiredHabitCount,
            requiredHabitsTotal: context.requiredHabits.count
        )
        state.lastSummaryDayKey = dayKey
        dailySummarySignal += 1
    }

    private func applyWeeklyGoalReward() {
        guard state.weeklyGoal.completed == false else { return }
        state.weeklyGoal.completed = true

        award(RewardDefinition(
            xp: 60,
            skillXP: [(.reliability, 15)],
            momentum: 10,
            reason: "Weekly goal completed"
        ))

        state.weeklyXPBonusUntil = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        state.weeklyXPBonusMultiplier = 1.10
    }

    private func applyRecoveryCompletion() {
        guard var recovery = state.recoveryChallenge else { return }
        recovery.completed = true
        state.recoveryChallenge = recovery
    }

    private func activateResetDay() {
        let currentWeek = GameState.weekKey(Date())
        guard state.resetDayUsedWeekKey != currentWeek else { return }
        guard state.resetDayChallenge.isActive == false else { return }

        let eligible = state.momentum < 30 || state.badDayStreak >= 3
        guard eligible else { return }

        state.resetDayChallenge = ResetDayChallengeState(
            isActive: true,
            weekKey: currentWeek,
            focusTarget: 2,
            taskTarget: 2,
            habitTarget: 1,
            focusProgress: 0,
            taskProgress: 0,
            habitProgress: 0
        )
    }

    private func trackResetProgress(focusDelta: Int, taskDelta: Int, habitDelta: Int) {
        guard state.resetDayChallenge.isActive else { return }

        state.resetDayChallenge.focusProgress = min(
            state.resetDayChallenge.focusTarget,
            state.resetDayChallenge.focusProgress + focusDelta
        )
        state.resetDayChallenge.taskProgress = min(
            state.resetDayChallenge.taskTarget,
            state.resetDayChallenge.taskProgress + taskDelta
        )
        state.resetDayChallenge.habitProgress = min(
            state.resetDayChallenge.habitTarget,
            state.resetDayChallenge.habitProgress + habitDelta
        )

        guard state.resetDayChallenge.isCompleted else { return }

        state.momentum = 50
        state.badDayStreak = 0
        state.pendingRecovery = nil
        state.recoveryChallenge = nil
        state.resetDayUsedWeekKey = GameState.weekKey(Date())
        state.resetDayChallenge.isActive = false
        state.resetDayChallenge.focusProgress = state.resetDayChallenge.focusTarget
        state.resetDayChallenge.taskProgress = state.resetDayChallenge.taskTarget
        state.resetDayChallenge.habitProgress = state.resetDayChallenge.habitTarget
    }

    private func settlePendingRecoveryIfNeeded(evaluatingDayKey: String) {
        guard let pending = state.pendingRecovery else { return }
        guard pending.dayKey != evaluatingDayKey else { return }

        if state.recoveryChallenge?.completed == true {
            let reducedXP = -3 * pending.missedCount
            let tinyMomentum = -min(2, pending.missedCount)
            award(RewardDefinition(
                xp: reducedXP,
                skillXP: [],
                momentum: tinyMomentum,
                reason: "Recovery challenge completed"
            ), applyMultiplier: false)
        } else {
            let fullXP = -10 * pending.missedCount
            let fullReliability = -5 * pending.missedCount
            let momentumLoss = -8 * pending.missedCount
            award(RewardDefinition(
                xp: fullXP,
                skillXP: [(.reliability, fullReliability)],
                momentum: momentumLoss,
                reason: "Missed daily tasks"
            ), applyMultiplier: false)
        }

        state.pendingRecovery = nil
        state.recoveryChallenge = nil
    }

    private func rewardAllDailyCompletion(dayKey: String) {
        let key = "\(dayKey)-all"
        guard state.rewardedDailyCompletionDayKeys.contains(key) == false else { return }
        state.rewardedDailyCompletionDayKeys.append(key)

        if state.weeklyDailyCompletionDayKeys.contains(dayKey) == false {
            state.weeklyDailyCompletionDayKeys.append(dayKey)
            state.weeklyGoal.completedDailyCompletions += 1
            state.lifetimeDailyCompletionDays += 1
        }

        var completionXP = 25
        if state.specialization.selection == .reliabilitySpecialist {
            completionXP += 10
        }

        award(RewardDefinition(
            xp: completionXP,
            skillXP: [(.reliability, 12)],
            momentum: 8,
            reason: "All daily tasks completed"
        ))
    }

    private func rewardCompletedDailyPacks(dayKey: String, dailyTasks: [TaskItem]) {
        let packs = Dictionary(grouping: dailyTasks.compactMap { task -> String? in
            task.tags.first(where: { $0.hasPrefix("pack:") })
        }, by: { $0 })

        for (packTag, tagEntries) in packs {
            guard tagEntries.isEmpty == false else { continue }

            let key = "\(dayKey)-\(packTag)"
            guard state.rewardedDailyPackKeys.contains(key) == false else { continue }

            let packTasks = dailyTasks.filter { $0.tags.contains(packTag) }
            guard packTasks.isEmpty == false, packTasks.allSatisfy({ $0.status == .done }) else { continue }

            state.rewardedDailyPackKeys.append(key)
            award(RewardDefinition(
                xp: 10,
                skillXP: [(.reliability, 4)],
                momentum: 2,
                reason: "Daily task pack completed"
            ))
        }
    }

    private func streakReward(for streak: Int) -> Int {
        let base: Int
        switch streak {
        case 3: base = 3
        case 7: base = 8
        case 14: base = 15
        case 30: base = 30
        default: base = 0
        }

        guard base > 0 else { return 0 }
        if state.specialization.selection == .routineSpecialist {
            return Int((Double(base) * 1.2).rounded())
        }
        return base
    }

    private func awardComboIfNeeded(dayKey: String, completedToday: Int) {
        let thresholds: [(Int, Int, Int)] = [
            (3, 8, 2),
            (5, 15, 3),
            (8, 25, 5)
        ]

        for (threshold, xpValue, momentumGain) in thresholds where completedToday == threshold {
            let key = "\(dayKey)-combo-\(threshold)"
            guard state.rewardedComboKeys.contains(key) == false else { continue }
            state.rewardedComboKeys.append(key)

            var finalXP = xpValue
            if state.specialization.selection == .executionSpecialist {
                finalXP += 5
            }

            award(RewardDefinition(
                xp: finalXP,
                skillXP: [],
                momentum: momentumGain,
                reason: "\(threshold)-task combo"
            ))
        }
    }

    private func markChallengeCompleted(id: UUID, cadence: ChallengeCadence) {
        switch cadence {
        case .daily:
            if let index = state.dailyChallenges.firstIndex(where: { $0.id == id }) {
                state.dailyChallenges[index].completed = true
            }
        case .weekly:
            if let index = state.weeklyChallenges.firstIndex(where: { $0.id == id }) {
                state.weeklyChallenges[index].completed = true
            }
        case .recovery:
            applyRecoveryCompletion()
        case .seasonal:
            if let index = state.seasonalChallenges.firstIndex(where: { $0.id == id }) {
                state.seasonalChallenges[index].completed = true
            }
        }
    }

    private func refreshChallengesAndAchievements() {
        refreshChallengeProgress(list: &state.dailyChallenges)
        refreshChallengeProgress(list: &state.weeklyChallenges)
        refreshChallengeProgress(list: &state.seasonalChallenges)

        let unlocks = AchievementEngine.computeNewAchievements(state: state)
        for unlock in unlocks {
            state.achievements.insert(unlock.achievement, at: 0)
            award(RewardDefinition(
                xp: unlock.xpReward,
                skillXP: [],
                momentum: 1,
                reason: "Achievement unlocked"
            ))
        }
    }

    private func refreshChallengeProgress(list: inout [DailyChallenge]) {
        var pendingRewards: [RewardDefinition] = []

        for index in list.indices {
            list[index].progress = challengeProgress(for: list[index])
            if list[index].progress >= list[index].target {
                list[index].completed = true
            }

            guard list[index].completed, list[index].rewarded == false else { continue }
            list[index].rewarded = true

            var xp = list[index].rewardXP
            if state.specialization.selection == .focusSpecialist,
               list[index].kind == .focusSessions || list[index].kind == .weeklyFocusVolume {
                xp += 5
            }

            pendingRewards.append(RewardDefinition(
                xp: xp,
                skillXP: ChallengeEngine.rewardSkillXP(for: list[index]),
                momentum: list[index].rewardMomentum,
                reason: list[index].title
            ))
        }

        for reward in pendingRewards {
            award(reward)
        }
    }

    private func challengeProgress(for challenge: DailyChallenge) -> Int {
        switch (challenge.cadence, challenge.kind) {
        case (.daily, .focusSessions):
            return min(challenge.target, state.completedFocusSessionKeys.count)
        case (.daily, .completeTasks):
            return min(challenge.target, state.completedNormalTaskIDs.count)
        case (.daily, .completeHabits):
            return min(challenge.target, state.completedHabitKeys.count)
        case (.daily, .completeDailyTasks):
            return min(challenge.target, state.completedDailyTaskIDs.count)
        case (.daily, .dailyPackCompletion):
            let today = GameState.dayKey(Date())
            let count = state.rewardedDailyPackKeys.filter { $0.hasPrefix("\(today)-pack:") }.count
            return min(challenge.target, count)
        case (.weekly, .weeklyConsistency), (.weekly, .completeDailyTasks):
            return min(challenge.target, state.weeklyDailyCompletionDayKeys.count)
        case (.weekly, .weeklyFocusVolume):
            return min(challenge.target, state.weeklyFocusSessions)
        case (.weekly, .perfectDay), (.daily, .perfectDay):
            let weekKey = GameState.weekKey(Date())
            let weekPerfect = state.perfectDayKeys.filter { key in
                guard let date = Self.dayDate(from: key) else { return false }
                return GameState.weekKey(date) == weekKey
            }.count
            return min(challenge.target, challenge.cadence == .weekly ? weekPerfect : (state.perfectDayKeys.contains(GameState.dayKey(Date())) ? 1 : 0))
        case (.seasonal, .seasonalMomentum):
            return min(challenge.target, state.season.stats.perfectDays)
        case (_, .recoveryWalk), (_, .recoveryClean), (_, .recoveryReflect):
            return state.recoveryChallenge?.completed == true ? challenge.target : 0
        default:
            return 0
        }
    }

    private func mapSkill(_ value: TaskSkillTag) -> SkillCategory {
        switch value {
        case .focus: return .focus
        case .execution: return .execution
        case .routine: return .routine
        case .reliability: return .reliability
        }
    }

    private func makeDailySummary(
        dayKey: String,
        allDailyDone: Bool,
        missedDailyCount: Int,
        perfectDay: Bool,
        focusGoalReached: Bool,
        requiredHabitsDone: Int,
        requiredHabitsTotal: Int
    ) -> String {
        let dailyStatus = allDailyDone ? "daily tasks complete" : "\(missedDailyCount) daily tasks missed"
        let focusStatus = focusGoalReached ? "focus goal reached" : "focus goal missed"
        let habitStatus = "required habits \(requiredHabitsDone)/\(requiredHabitsTotal)"
        let perfect = perfectDay ? "perfect day achieved" : "no perfect day"
        return "\(dayKey): \(dailyStatus), \(focusStatus), \(habitStatus), \(perfect). Momentum \(state.momentum)."
    }

    private func award(_ reward: RewardDefinition, applyMultiplier: Bool = true) {
        var effectiveXP = reward.xp
        if reward.xp > 0 && applyMultiplier {
            let momentumMultiplier = MomentumState(value: state.momentum).xpMultiplier
            let weeklyMultiplier = weeklyMultiplierForNow()
            let stacked = min(1.18, momentumMultiplier * weeklyMultiplier)
            effectiveXP = Int((Double(reward.xp) * stacked).rounded())
        }

        if effectiveXP != 0 {
            state.totalXP = max(0, state.totalXP + effectiveXP)
            state.season.seasonalXP = max(0, state.season.seasonalXP + max(0, effectiveXP))
        }

        for (skill, delta) in reward.skillXP {
            applySkillOnly(skill, delta: delta)
        }

        state.momentum = MomentumEngine.apply(reward.momentum, to: state.momentum)
        state.level = ProgressionEngine.level(forXP: state.totalXP)

        RewardPresentationCoordinator.pushEntry(
            RewardDefinition(
                xp: effectiveXP,
                skillXP: reward.skillXP,
                momentum: reward.momentum,
                reason: reward.reason
            ),
            into: &state.xpEntries,
            totalXP: state.totalXP,
            level: state.level
        )
    }

    private func applySkillOnly(_ category: SkillCategory, delta: Int) {
        var progress = state.skills[category]

        var effective = delta
        if delta > 0 {
            if category == .focus, state.specialization.selection == .focusSpecialist {
                effective += Int((Double(delta) * 0.10).rounded())
            }
            if category == .routine, state.specialization.selection == .routineSpecialist {
                effective += Int((Double(delta) * 0.10).rounded())
            }
            if category == .reliability, state.specialization.selection == .reliabilitySpecialist {
                effective += Int((Double(delta) * 0.10).rounded())
            }
        }

        progress.xp = max(0, progress.xp + effective)
        state.skills[category] = progress
    }

    private func weeklyMultiplierForNow() -> Double {
        guard let until = state.weeklyXPBonusUntil else { return 1.0 }
        if until < Date() {
            state.weeklyXPBonusUntil = nil
            state.weeklyXPBonusMultiplier = 1.0
            return 1.0
        }
        return max(1.0, state.weeklyXPBonusMultiplier)
    }

    private func ensureDailyState(now: Date) {
        let dayKey = GameState.dayKey(now)
        if state.dailyChallenges.first?.dayKey != dayKey {
            state.dailyChallenges = ChallengeEngine.generateDailyChallenges(for: dayKey, state: state)
            state.completedDailyTaskIDs = []
            state.completedNormalTaskIDs = []
            state.completedHabitKeys = []
            state.completedFocusSessionKeys = []
            state.overduePenaltyByDay = [:]
        }

        let weekKey = GameState.weekKey(now)
        if state.weeklyGoal.weekKey != weekKey {
            state.weeklyGoal = WeeklyGoalState(
                weekKey: weekKey,
                requiredDailyCompletions: 5,
                completedDailyCompletions: 0,
                completed: false
            )
            state.weeklyChallenges = ChallengeEngine.generateWeeklyChallenges(for: weekKey, state: state)
            state.weeklyDailyCompletionDayKeys = []
            state.weeklyFocusSessions = 0
            state.weeklyTaskCompletions = 0
            state.weeklyHabitCompletions = 0
            state.weeklyPerfectDays = 0
            if state.resetDayChallenge.weekKey != weekKey {
                state.resetDayChallenge = .empty(weekKey: weekKey)
            }
        }

        if now > state.season.endDate {
            state.season = SeasonEngine.currentSeason(now: now)
            state.seasonalChallenges = ChallengeEngine.generateSeasonalChallenges(for: state.season)
        } else if state.seasonalChallenges.isEmpty {
            state.seasonalChallenges = ChallengeEngine.generateSeasonalChallenges(for: state.season)
        }
    }

    private func recalculateDerived() {
        state.level = ProgressionEngine.level(forXP: state.totalXP)

        totalXP = state.totalXP
        level = state.level
        momentum = state.momentum
        skills = state.skills
        dailyChallenges = state.dailyChallenges
        weeklyChallenges = state.weeklyChallenges
        seasonalChallenges = state.seasonalChallenges
        recoveryChallenge = state.recoveryChallenge
        achievements = state.achievements
        xpEntries = state.xpEntries
        specialization = state.specialization
        season = state.season
        weeklyGoal = state.weeklyGoal
        resetDayChallenge = state.resetDayChallenge
        lastModifiedAt = state.lastModifiedAt
    }

    private func commitMutation(reason: String) {
        _ = reason
        guard isApplyingCloudSnapshot == false else {
            recalculateDerived()
            persist()
            return
        }

        state.lastModifiedAt = Date()
        recalculateDerived()
        persist()
        onDataChanged?()
    }

    private func persist() {
        storage.save(State(game: state), to: fileName)
    }

    private static func migrateLegacy(_ legacy: LegacyGameState, now: Date) -> GameState {
        let weekKey = GameState.weekKey(now)
        var migrated = GameState.empty(now: now)

        migrated.totalXP = max(0, legacy.totalXP)
        migrated.level = max(1, legacy.level)
        migrated.momentum = min(100, max(0, legacy.momentum))
        migrated.skills = legacy.skills
        migrated.dailyChallenges = legacy.dailyChallenges
        migrated.weeklyChallenges = legacy.weeklyChallenges
        migrated.recoveryChallenge = legacy.recoveryChallenge
        migrated.weeklyGoal = legacy.weeklyGoal
        migrated.specialization = legacy.specialization
        migrated.season = legacy.season
        migrated.achievements = legacy.achievements
        migrated.xpEntries = legacy.xpEntries
        migrated.completedDailyTaskIDs = legacy.completedDailyTaskIDs
        migrated.completedNormalTaskIDs = legacy.completedNormalTaskIDs
        migrated.completedHabitKeys = legacy.completedHabitKeys
        migrated.completedFocusSessionKeys = legacy.completedFocusSessionKeys
        migrated.perfectDayKeys = legacy.perfectDayKeys
        migrated.badDayStreak = legacy.badDayStreak
        migrated.resetDayUsedWeekKey = legacy.resetDayUsedWeekKey
        migrated.weeklyXPBonusUntil = legacy.weeklyXPBonusUntil
        migrated.weeklyXPBonusMultiplier = legacy.weeklyXPBonusMultiplier
        migrated.lastEvaluatedDayKey = legacy.lastEvaluatedDayKey
        migrated.lastModifiedAt = max(legacy.lastModifiedAt, now)

        migrated.lifetimeFocusSessions = legacy.completedFocusSessionKeys.count
        migrated.lifetimeTaskCompletions = legacy.completedNormalTaskIDs.count
        migrated.lifetimeHabitCompletions = legacy.completedHabitKeys.count
        migrated.lifetimeRequiredHabitCompletions = 0
        migrated.lifetimeDailyCompletionDays = legacy.weeklyGoal.completedDailyCompletions
        migrated.weeklyDailyCompletionDayKeys = []
        migrated.weeklyFocusSessions = 0
        migrated.weeklyTaskCompletions = 0
        migrated.weeklyHabitCompletions = 0
        migrated.weeklyPerfectDays = 0
        migrated.resetDayChallenge = .empty(weekKey: weekKey)
        migrated.seasonalChallenges = ChallengeEngine.generateSeasonalChallenges(for: migrated.season)

        return migrated
    }

    private static func dayDate(from key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }
}
