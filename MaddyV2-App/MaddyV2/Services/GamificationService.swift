//
//  GamificationService.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import Foundation
import SwiftUI
import Combine

// =====================================================
// MARK: - Skill Axis
// [TAG: V2_GAMIFICATION_SKILLS]
// =====================================================

enum GamificationSkillAxis: String, Codable, CaseIterable, Identifiable {
    case focus
    case execution
    case routine
    case reliability

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

struct GamificationSkillState: Codable, Equatable {
    var totalXP: Int = 0

    var skillLevel: Int {
        Self.level(forXP: totalXP)
    }

    var skillXP: Int {
        max(0, totalXP - Self.totalXPRequired(toReach: skillLevel))
    }

    var xpToNextLevel: Int {
        Self.xpNeededForNextLevel(level: skillLevel)
    }

    var skillProgress0to1: Double {
        let needed = Double(max(1, xpToNextLevel))
        return min(1.0, Double(skillXP) / needed)
    }

    var normalized0to1: Double {
        min(1.0, Double(skillLevel) / 20.0)
    }

    static func xpNeededForNextLevel(level: Int) -> Int {
        let safe = max(1, level)
        let step = safe - 1
        return 50 + (step * 20) + (step * step * 3)
    }

    static func totalXPRequired(toReach level: Int) -> Int {
        guard level > 1 else { return 0 }
        var total = 0
        for idx in 1..<level {
            total += xpNeededForNextLevel(level: idx)
        }
        return total
    }

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
            if level > 300 {
                return level
            }
        }
    }
}

// =====================================================
// MARK: - Gamification Domain
// [TAG: V2_GAMIFICATION_DOMAIN]
// =====================================================

enum GamificationSpecialization: String, Codable, CaseIterable, Identifiable {
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

enum GamificationChallengeCadence: String, Codable {
    case daily
    case weekly
    case recovery
    case seasonal
}

enum GamificationChallengeDifficulty: String, Codable {
    case easy
    case medium
    case hard
}

enum GamificationChallengeKind: String, Codable {
    case earlyWin
    case consistency
    case taskSprint
    case habitCombo
    case cleanInbox
    case deepFocus
    case studySession
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
}

struct GamificationDailyChallenge: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var detail: String
    var cadence: GamificationChallengeCadence
    var kind: GamificationChallengeKind
    var difficulty: GamificationChallengeDifficulty
    var target: Int
    var progress: Int
    var rewardXP: Int
    var rewardMomentum: Int
    var completed: Bool
    var rewarded: Bool
    var dayKey: String

    var description: String {
        get { detail }
        set { detail = newValue }
    }

    init(
        id: UUID,
        title: String,
        detail: String,
        cadence: GamificationChallengeCadence,
        kind: GamificationChallengeKind,
        difficulty: GamificationChallengeDifficulty,
        target: Int,
        progress: Int,
        rewardXP: Int,
        rewardMomentum: Int,
        completed: Bool,
        rewarded: Bool,
        dayKey: String
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.cadence = cadence
        self.kind = kind
        self.difficulty = difficulty
        self.target = target
        self.progress = progress
        self.rewardXP = rewardXP
        self.rewardMomentum = rewardMomentum
        self.completed = completed
        self.rewarded = rewarded
        self.dayKey = dayKey
    }

    init(
        id: String,
        kind: GamificationChallengeKind,
        title: String,
        description: String,
        rewardXP: Int,
        progress: Int,
        target: Int,
        completed: Bool,
        rewarded: Bool
    ) {
        self.id = UUID(uuidString: id) ?? UUID()
        self.title = title
        self.detail = description
        self.cadence = .daily
        self.kind = kind
        self.difficulty = .medium
        self.target = target
        self.progress = progress
        self.rewardXP = rewardXP
        self.rewardMomentum = 0
        self.completed = completed
        self.rewarded = rewarded
        self.dayKey = Self.dayKey(Date())
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct GamificationRecoveryChallenge: Codable, Equatable {
    enum Category: String, Codable {
        case physical
        case cleaning
        case reflection
    }

    var id: UUID
    var title: String
    var detail: String
    var category: Category
    var severity: Int
    var completed: Bool
    var expiresAt: Date
    var sourceTaskID: UUID?
}

struct GamificationPendingRecoveryState: Codable, Equatable {
    var dayKey: String
    var missedCount: Int
    var createdAt: Date
}

struct GamificationResetDayChallengeState: Codable, Equatable {
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

    static func empty(weekKey: String) -> GamificationResetDayChallengeState {
        GamificationResetDayChallengeState(
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

struct GamificationWeeklyGoalState: Codable, Equatable {
    var weekKey: String
    var requiredDailyCompletions: Int
    var completedDailyCompletions: Int
    var completed: Bool
}

struct GamificationSpecializationState: Codable, Equatable {
    var selection: GamificationSpecialization
    var lastChangedAt: Date?
}

struct GamificationSeasonStats: Codable, Equatable {
    var focusSessions: Int
    var tasksDone: Int
    var habitsDone: Int
    var perfectDays: Int

    static let zero = GamificationSeasonStats(focusSessions: 0, tasksDone: 0, habitsDone: 0, perfectDays: 0)
}

struct GamificationSeasonState: Codable, Equatable {
    var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var seasonalXP: Int
    var badgeUnlocked: Bool
    var unlockedTitles: [String]
    var unlockedPackIDs: [String]
    var stats: GamificationSeasonStats

    init(
        id: UUID,
        title: String,
        startDate: Date,
        endDate: Date,
        seasonalXP: Int,
        badgeUnlocked: Bool,
        unlockedTitles: [String] = [],
        unlockedPackIDs: [String] = [],
        stats: GamificationSeasonStats = .zero
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.seasonalXP = seasonalXP
        self.badgeUnlocked = badgeUnlocked
        self.unlockedTitles = unlockedTitles
        self.unlockedPackIDs = unlockedPackIDs
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
        case unlockedPackIDs
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
        unlockedPackIDs = try c.decodeIfPresent([String].self, forKey: .unlockedPackIDs) ?? []
        stats = try c.decodeIfPresent(GamificationSeasonStats.self, forKey: .stats) ?? .zero
    }
}

struct GamificationAchievementRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var detail: String
    var icon: String
    var unlockedAt: Date
    var tier: String
    var hidden: Bool
    var rewardTitle: String?
    var rewardCosmetic: String?

    init(
        id: UUID,
        title: String,
        detail: String,
        icon: String,
        unlockedAt: Date,
        tier: String = "small",
        hidden: Bool = false,
        rewardTitle: String? = nil,
        rewardCosmetic: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.icon = icon
        self.unlockedAt = unlockedAt
        self.tier = tier
        self.hidden = hidden
        self.rewardTitle = rewardTitle
        self.rewardCosmetic = rewardCosmetic
    }
}

struct GamificationXPEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date
    var delta: Int
    var totalXP: Int
    var level: Int
    var reason: String
}

struct GamificationDayEvaluation {
    var date: Date
    var dailyTasks: [TaskItem]
    var requiredHabitCount: Int
    var completedRequiredHabitCount: Int
    var focusGoalReached: Bool
    var completedNormalTaskCount: Int
}

private struct GamificationRewardDefinition {
    var xp: Int
    var skillXP: [(GamificationSkillAxis, Int)]
    var momentum: Int
    var reason: String
}

private struct GamificationAchievementUnlock {
    var record: GamificationAchievementRecord
    var xpReward: Int
}

// =====================================================
// MARK: - Service
// [TAG: V2_GAMIFICATION_SERVICE]
// =====================================================

@MainActor
final class GamificationService: ObservableObject {
    @Published private(set) var totalXP: Int = 0
    @Published private(set) var momentum: Int = 50
    @Published private(set) var dailyFocusStreak: Int = 0
    @Published private(set) var skills: [GamificationSkillAxis: GamificationSkillState] = [:]

    @Published private(set) var dailyChallenges: [GamificationDailyChallenge] = []
    @Published private(set) var weeklyChallenges: [GamificationDailyChallenge] = []
    @Published private(set) var seasonalChallenges: [GamificationDailyChallenge] = []
    @Published private(set) var recoveryChallenge: GamificationRecoveryChallenge?

    @Published private(set) var achievements: [GamificationAchievementRecord] = []
    @Published private(set) var xpEntries: [GamificationXPEntry] = []

    @Published private(set) var specialization: GamificationSpecializationState = .init(selection: .none, lastChangedAt: nil)
    @Published private(set) var season: GamificationSeasonState = GamificationService.currentSeason(now: Date())
    @Published private(set) var weeklyGoal: GamificationWeeklyGoalState = .init(weekKey: "", requiredDailyCompletions: 5, completedDailyCompletions: 0, completed: false)
    @Published private(set) var resetDayChallenge: GamificationResetDayChallengeState = .empty(weekKey: GamificationService.weekKey(Date()))

    @Published private(set) var dailySummaryText: String?
    @Published private(set) var dailySummarySignal: Int = 0

    @Published private(set) var challengeCelebrationToken: Int = 0
    @Published private(set) var lastCompletedChallengeID: String?

    private var completedDailyTaskIDs: [UUID] = []
    private var completedNormalTaskIDs: [UUID] = []
    private var completedHabitKeys: [String] = []
    private var completedFocusSessionKeys: [String] = []
    private var perfectDayKeys: [String] = []

    private var rewardedFocusThreeSessionDayKeys: [String] = []
    private var rewardedFocusGoalDayKeys: [String] = []
    private var rewardedComboKeys: [String] = []
    private var rewardedDailyCompletionDayKeys: [String] = []
    private var rewardedDailyPackKeys: [String] = []
    private var rewardedMilestoneKeys: [String] = []

    private var pendingRecovery: GamificationPendingRecoveryState?

    private var weeklyDailyCompletionDayKeys: [String] = []
    private var weeklyFocusSessions = 0
    private var weeklyTaskCompletions = 0
    private var weeklyHabitCompletions = 0
    private var weeklyPerfectDays = 0

    private var lifetimeFocusSessions = 0
    private var lifetimeTaskCompletions = 0
    private var lifetimeHabitCompletions = 0
    private var lifetimeRequiredHabitCompletions = 0
    private var lifetimeDailyCompletionDays = 0

    private var badDayStreak = 0
    private var resetDayUsedWeekKey: String?
    private var weeklyXPBonusUntil: Date?
    private var weeklyXPBonusMultiplier: Double = 1.0

    private var overduePenaltyByDay: [String: Int] = [:]

    private var lastEvaluatedDayKey: String?
    private var lastSummaryDayKey: String?
    private var lastModifiedAt: Date = .distantPast

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileURL: URL

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        fileURL = JSONStorageService.baseDirectory.appendingPathComponent("gamification_v2.json")

        skills = Dictionary(uniqueKeysWithValues: GamificationSkillAxis.allCases.map { ($0, GamificationSkillState()) })
        weeklyGoal = .init(weekKey: Self.weekKey(Date()), requiredDailyCompletions: 5, completedDailyCompletions: 0, completed: false)

        load()
        ensureDailyState(now: Date())
        persist()
    }

    // =====================================================
    // MARK: - Public Derived State
    // [TAG: V2_GAMIFICATION_DERIVED]
    // =====================================================

    var currentLevel: Int {
        Self.level(forXP: totalXP)
    }

    var level: Int { currentLevel }

    var xpInLevel: Int {
        max(0, totalXP - Self.totalXPRequired(toReach: currentLevel))
    }

    var xpToNextLevel: Int {
        Self.xpNeededForNextLevel(level: currentLevel)
    }

    var progress0to1: Double {
        let needed = Double(max(1, xpToNextLevel))
        return min(1.0, Double(xpInLevel) / needed)
    }

    var progressToNextLevel: Double {
        progress0to1
    }

    var skillPoints: Int {
        0
    }

    var reliabilityNormalized: Int {
        let value = skills[.reliability]?.normalized0to1 ?? 0
        return Int((value * 100.0).rounded())
    }

    func spendSkillPoint(on axis: GamificationSkillAxis) -> Bool {
        _ = axis
        return false
    }

    // =====================================================
    // MARK: - Cloud Snapshot
    // [TAG: V2_GAMIFICATION_CLOUD_SYNC]
    // =====================================================

    struct CloudSnapshot: Codable, Equatable {
        var game: CloudGameState
        var modifiedAt: Date
    }

    struct CloudSkillProgress: Codable, Equatable {
        var xp: Int
    }

    struct CloudSkillValues: Codable, Equatable {
        var focus: CloudSkillProgress
        var execution: CloudSkillProgress
        var routine: CloudSkillProgress
        var reliability: CloudSkillProgress
    }

    struct CloudGameState: Codable, Equatable {
        var totalXP: Int
        var level: Int
        var momentum: Int
        var skills: CloudSkillValues

        var dailyChallenges: [GamificationDailyChallenge]
        var weeklyChallenges: [GamificationDailyChallenge]
        var seasonalChallenges: [GamificationDailyChallenge]
        var recoveryChallenge: GamificationRecoveryChallenge?
        var pendingRecovery: GamificationPendingRecoveryState?

        var weeklyGoal: GamificationWeeklyGoalState
        var specialization: GamificationSpecializationState
        var season: GamificationSeasonState

        var achievements: [GamificationAchievementRecord]
        var xpEntries: [GamificationXPEntry]

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
        var resetDayChallenge: GamificationResetDayChallengeState

        var weeklyXPBonusUntil: Date?
        var weeklyXPBonusMultiplier: Double

        var overduePenaltyByDay: [String: Int]

        var lastEvaluatedDayKey: String?
        var lastSummaryDayKey: String?
        var lastModifiedAt: Date
    }

    func cloudSnapshot() -> CloudSnapshot {
        let state = CloudGameState(
            totalXP: totalXP,
            level: currentLevel,
            momentum: momentum,
            skills: CloudSkillValues(
                focus: .init(xp: skills[.focus]?.totalXP ?? 0),
                execution: .init(xp: skills[.execution]?.totalXP ?? 0),
                routine: .init(xp: skills[.routine]?.totalXP ?? 0),
                reliability: .init(xp: skills[.reliability]?.totalXP ?? 0)
            ),
            dailyChallenges: dailyChallenges,
            weeklyChallenges: weeklyChallenges,
            seasonalChallenges: seasonalChallenges,
            recoveryChallenge: recoveryChallenge,
            pendingRecovery: pendingRecovery,
            weeklyGoal: weeklyGoal,
            specialization: specialization,
            season: season,
            achievements: achievements,
            xpEntries: xpEntries,
            completedDailyTaskIDs: completedDailyTaskIDs,
            completedNormalTaskIDs: completedNormalTaskIDs,
            completedHabitKeys: completedHabitKeys,
            completedFocusSessionKeys: completedFocusSessionKeys,
            perfectDayKeys: perfectDayKeys,
            rewardedFocusThreeSessionDayKeys: rewardedFocusThreeSessionDayKeys,
            rewardedFocusGoalDayKeys: rewardedFocusGoalDayKeys,
            rewardedComboKeys: rewardedComboKeys,
            rewardedDailyCompletionDayKeys: rewardedDailyCompletionDayKeys,
            rewardedDailyPackKeys: rewardedDailyPackKeys,
            rewardedMilestoneKeys: rewardedMilestoneKeys,
            weeklyDailyCompletionDayKeys: weeklyDailyCompletionDayKeys,
            weeklyFocusSessions: weeklyFocusSessions,
            weeklyTaskCompletions: weeklyTaskCompletions,
            weeklyHabitCompletions: weeklyHabitCompletions,
            weeklyPerfectDays: weeklyPerfectDays,
            lifetimeFocusSessions: lifetimeFocusSessions,
            lifetimeTaskCompletions: lifetimeTaskCompletions,
            lifetimeHabitCompletions: lifetimeHabitCompletions,
            lifetimeRequiredHabitCompletions: lifetimeRequiredHabitCompletions,
            lifetimeDailyCompletionDays: lifetimeDailyCompletionDays,
            badDayStreak: badDayStreak,
            resetDayUsedWeekKey: resetDayUsedWeekKey,
            resetDayChallenge: resetDayChallenge,
            weeklyXPBonusUntil: weeklyXPBonusUntil,
            weeklyXPBonusMultiplier: weeklyXPBonusMultiplier,
            overduePenaltyByDay: overduePenaltyByDay,
            lastEvaluatedDayKey: lastEvaluatedDayKey,
            lastSummaryDayKey: lastSummaryDayKey,
            lastModifiedAt: lastModifiedAt
        )
        return CloudSnapshot(game: state, modifiedAt: lastModifiedAt)
    }

    func applyCloudSnapshot(_ snapshot: CloudSnapshot) {
        guard snapshot.modifiedAt > lastModifiedAt else { return }
        applyCloudGameState(snapshot.game, modifiedAt: snapshot.modifiedAt)
        persist()
    }

    // =====================================================
    // MARK: - Integration Hooks
    // [TAG: V2_GAMIFICATION_HOOKS]
    // =====================================================

    func registerFocusSession(_ entry: FocusLogEntry, dailyGoal: Int, allLogs: [FocusLogEntry]) {
        let durationMinutes = max(1, entry.durationSeconds / 60)
        guard durationMinutes > 0 else { return }

        let dayKey = Self.dayKey(entry.startedAt)
        let uniqueKey = "\(entry.id.uuidString)-\(dayKey)"
        guard completedFocusSessionKeys.contains(uniqueKey) == false else { return }

        completedFocusSessionKeys.append(uniqueKey)
        lifetimeFocusSessions += 1
        weeklyFocusSessions += 1
        season.stats.focusSessions += 1

        award(.init(xp: 10, skillXP: [(.focus, 10)], momentum: 1, reason: "Focus session completed"))

        let sessionsToday = allLogs.filter {
            ($0.phase == .work || $0.phase == .custom) && Self.dayKey($0.startedAt) == dayKey
        }.count

        if sessionsToday == 3 {
            let bonusKey = "\(dayKey)-focus3"
            if rewardedFocusThreeSessionDayKeys.contains(bonusKey) == false {
                rewardedFocusThreeSessionDayKeys.append(bonusKey)
                award(.init(xp: 10, skillXP: [(.focus, 5)], momentum: 3, reason: "3 focus sessions in one day"))
            }
        }

        if sessionsToday >= max(1, dailyGoal) {
            let goalKey = "\(dayKey)-focusgoal"
            if rewardedFocusGoalDayKeys.contains(goalKey) == false {
                rewardedFocusGoalDayKeys.append(goalKey)
                award(.init(xp: 15, skillXP: [(.focus, 8)], momentum: 4, reason: "Focus daily goal reached"))
            }
        }

        trackResetProgress(focusDelta: 1, taskDelta: 0, habitDelta: 0)
        recomputeFocusStreak(from: allLogs, dailyGoal: dailyGoal)

        refreshChallengesAndAchievements()
        commitMutation()
    }

    func registerTaskCompletion(_ task: TaskItem, completedToday: Int) {
        let dayKey = Self.dayKey(task.completedAt ?? Date())

        if task.isDailyTask {
            guard completedDailyTaskIDs.contains(task.id) == false else { return }
            completedDailyTaskIDs.append(task.id)

            var skillRewards: [(GamificationSkillAxis, Int)] = [(.reliability, 10)]
            let mapped = task.mappedSkills.isEmpty ? [.reliability] : Array(task.mappedSkills.prefix(2))
            if mapped.count == 1 {
                skillRewards.append((mapTaskSkill(mapped[0]), 6))
            } else {
                skillRewards.append((mapTaskSkill(mapped[0]), 3))
                skillRewards.append((mapTaskSkill(mapped[1]), 3))
            }

            award(.init(xp: 20, skillXP: skillRewards, momentum: 2, reason: "Daily task completed"))
            trackResetProgress(focusDelta: 0, taskDelta: 1, habitDelta: 0)

            refreshChallengesAndAchievements()
            commitMutation()
            return
        }

        guard completedNormalTaskIDs.contains(task.id) == false else { return }
        completedNormalTaskIDs.append(task.id)
        lifetimeTaskCompletions += 1
        weeklyTaskCompletions += 1
        season.stats.tasksDone += 1

        var xp = task.difficulty.xpReward + task.priorityBonus
        if task.difficulty == .hard, specialization.selection == .executionSpecialist {
            xp += 5
        }

        let mapped = task.mappedSkills.isEmpty ? [.execution] : Array(task.mappedSkills.prefix(2))
        let skillRewards: [(GamificationSkillAxis, Int)]
        if mapped.count == 1 {
            skillRewards = [(mapTaskSkill(mapped[0]), xp)]
        } else {
            let first = xp / 2
            let second = xp - first
            skillRewards = [(mapTaskSkill(mapped[0]), max(1, first)), (mapTaskSkill(mapped[1]), max(1, second))]
        }

        award(.init(xp: xp, skillXP: skillRewards, momentum: 0, reason: "Task completed"))
        awardComboIfNeeded(dayKey: dayKey, completedToday: completedToday)

        if isOverdueCompletion(task) {
            let applied = overduePenaltyByDay[dayKey, default: 0]
            if applied > -9 {
                overduePenaltyByDay[dayKey] = max(-9, applied - 3)
                applySkillOnly(.reliability, delta: -3)
            }
        }

        trackResetProgress(focusDelta: 0, taskDelta: 1, habitDelta: 0)

        refreshChallengesAndAchievements()
        commitMutation()
    }

    func registerHabitCompletion(_ habit: HabitItem, isRequired: Bool) {
        let dayKey = Self.dayKey(Date())
        let uniqueKey = "\(habit.id.uuidString)-\(dayKey)"
        guard completedHabitKeys.contains(uniqueKey) == false else { return }
        completedHabitKeys.append(uniqueKey)

        lifetimeHabitCompletions += 1
        weeklyHabitCompletions += 1
        season.stats.habitsDone += 1

        let weightXP: Int
        switch habit.targetPerDay {
        case ..<2: weightXP = 6
        case 2...4: weightXP = 10
        default: weightXP = 14
        }

        var skillRewards: [(GamificationSkillAxis, Int)] = [(.routine, weightXP)]
        if isRequired {
            skillRewards.append((.reliability, 2))
            lifetimeRequiredHabitCompletions += 1
        }

        award(.init(xp: weightXP, skillXP: skillRewards, momentum: 0, reason: "Habit completed"))

        let streak = currentHabitStreak(habit)
        let streakXP = streakReward(for: streak)
        if streakXP > 0 {
            award(.init(xp: streakXP, skillXP: [], momentum: 0, reason: "Habit streak reward"))
        }

        trackResetProgress(focusDelta: 0, taskDelta: 0, habitDelta: 1)

        refreshChallengesAndAchievements()
        commitMutation()
    }

    func registerMissedDailyTask(_ task: TaskItem) {
        let dayKey = task.effectiveDailyKey
        let nextCount: Int

        if let pendingRecovery, pendingRecovery.dayKey == dayKey {
            nextCount = pendingRecovery.missedCount + 1
        } else {
            nextCount = 1
        }

        pendingRecovery = .init(dayKey: dayKey, missedCount: min(6, nextCount), createdAt: Date())
        recoveryChallenge = Self.makeRecoveryChallenge(severity: min(3, nextCount), sourceTaskID: task.id)

        commitMutation()
    }

    func evaluateDay(_ context: GamificationDayEvaluation) {
        let dayKey = Self.dayKey(context.date)
        guard lastEvaluatedDayKey != dayKey else { return }
        lastEvaluatedDayKey = dayKey

        settlePendingRecoveryIfNeeded(evaluatingDayKey: dayKey)

        let missedDailyCount = context.dailyTasks.filter { $0.status != .done }.count
        if missedDailyCount > 0 {
            pendingRecovery = .init(dayKey: dayKey, missedCount: missedDailyCount, createdAt: Date())
            if recoveryChallenge == nil || recoveryChallenge?.completed == true {
                recoveryChallenge = Self.makeRecoveryChallenge(severity: min(3, missedDailyCount), sourceTaskID: nil)
            }
        }

        if context.focusGoalReached == false {
            adjustMomentum(-4)
        }

        if context.completedRequiredHabitCount < context.requiredHabitCount {
            adjustMomentum(-3)
        }

        let allDailyDone = context.dailyTasks.isEmpty == false && context.dailyTasks.allSatisfy { $0.status == .done }
        if allDailyDone {
            rewardAllDailyCompletion(dayKey: dayKey)
            rewardCompletedDailyPacks(dayKey: dayKey, dailyTasks: context.dailyTasks)
        }

        let perfectDay = allDailyDone &&
            context.focusGoalReached &&
            context.completedNormalTaskCount >= 1 &&
            context.requiredHabitCount > 0 &&
            context.completedRequiredHabitCount >= context.requiredHabitCount &&
            missedDailyCount == 0

        if perfectDay, perfectDayKeys.contains(dayKey) == false {
            perfectDayKeys.append(dayKey)
            weeklyPerfectDays += 1
            season.stats.perfectDays += 1
            award(.init(xp: 30, skillXP: [(.reliability, 5)], momentum: 10, reason: "Perfect day"))
            badDayStreak = 0
        } else if missedDailyCount > 0 || context.focusGoalReached == false || context.completedRequiredHabitCount < context.requiredHabitCount {
            badDayStreak = min(7, badDayStreak + 1)
        }

        if weeklyGoal.completed == false,
           weeklyGoal.completedDailyCompletions >= weeklyGoal.requiredDailyCompletions {
            applyWeeklyGoalReward()
        }

        dailySummaryText = makeDailySummary(
            dayKey: dayKey,
            allDailyDone: allDailyDone,
            missedDailyCount: missedDailyCount,
            perfectDay: perfectDay,
            focusGoalReached: context.focusGoalReached,
            requiredHabitsDone: context.completedRequiredHabitCount,
            requiredHabitsTotal: context.requiredHabitCount
        )
        lastSummaryDayKey = dayKey
        dailySummarySignal += 1

        refreshChallengesAndAchievements()
        commitMutation()
    }

    func completeRecoveryChallenge() {
        guard var challenge = recoveryChallenge else { return }
        challenge.completed = true
        recoveryChallenge = challenge
        commitMutation()
    }

    func activateResetDayIfAvailable() {
        let currentWeek = Self.weekKey(Date())
        guard resetDayUsedWeekKey != currentWeek else { return }
        guard resetDayChallenge.isActive == false else { return }

        let eligible = momentum < 30 || badDayStreak >= 3
        guard eligible else { return }

        resetDayChallenge = .init(
            isActive: true,
            weekKey: currentWeek,
            focusTarget: 2,
            taskTarget: 2,
            habitTarget: 1,
            focusProgress: 0,
            taskProgress: 0,
            habitProgress: 0
        )
        commitMutation()
    }

    func setSpecialization(_ next: GamificationSpecialization, at date: Date = Date()) -> Bool {
        guard next != specialization.selection else { return false }

        let maxLevel = GamificationSkillAxis.allCases.map { skills[$0]?.skillLevel ?? 1 }.max() ?? 1
        guard maxLevel >= 10 else { return false }

        if let last = specialization.lastChangedAt {
            let months = Calendar.current.dateComponents([.month], from: last, to: date).month ?? 0
            guard months >= 1 else { return false }
        }

        specialization = .init(selection: next, lastChangedAt: date)
        commitMutation()
        return true
    }

    func generateSmartDailyTaskTemplates() -> [TaskItem] {
        let todayKey = TaskItem.dayKey(Date())
        let now = Date()

        let pack = preferredPack()
        var seenTitles = Set<String>()
        var templates = DailyTaskLibrary.tasks(
            pack: pack,
            count: 2,
            dayKey: todayKey,
            date: now
        )
        templates.forEach { seenTitles.insert($0.title.lowercased()) }

        let focusLevel = skills[.focus]?.skillLevel ?? 1
        let executionLevel = skills[.execution]?.skillLevel ?? 1
        let routineLevel = skills[.routine]?.skillLevel ?? 1
        let reliabilityLevel = skills[.reliability]?.skillLevel ?? 1

        if focusLevel >= executionLevel + 2 {
            appendFirstAvailable(
                into: &templates,
                seenTitles: &seenTitles,
                candidates: DailyTaskLibrary.tasks(
                    pack: "productivity",
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
                    pack: "routine",
                    count: 2,
                    dayKey: todayKey,
                    date: now,
                    excludingTitles: seenTitles,
                    matchingAnyTags: ["routine-recovery", "habit"]
                )
            )
        }

        if momentum < 40 {
            appendFirstAvailable(
                into: &templates,
                seenTitles: &seenTitles,
                candidates: DailyTaskLibrary.tasks(
                    pack: "reset",
                    count: 3,
                    dayKey: todayKey,
                    date: now,
                    excludingTitles: seenTitles,
                    matchingAnyTags: ["recovery-reset", "reliability-rebuild"]
                )
            )
        }

        if executionLevel >= focusLevel + 3 {
            appendFirstAvailable(
                into: &templates,
                seenTitles: &seenTitles,
                candidates: DailyTaskLibrary.tasks(
                    pack: "student",
                    count: 2,
                    dayKey: todayKey,
                    date: now,
                    excludingTitles: seenTitles,
                    matchingAnyTags: ["focus-gap", "study"]
                ) + DailyTaskLibrary.tasks(
                    pack: "reset",
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

    func recomputeFocusStreak(from logs: [FocusLogEntry], dailyGoal: Int) {
        let goal = max(1, dailyGoal)
        var streak = 0
        var cursor = Calendar.current.startOfDay(for: Date())

        while true {
            let count = logs.filter {
                ($0.phase == .work || $0.phase == .custom) && Calendar.current.isDate($0.startedAt, inSameDayAs: cursor)
            }.count
            if count >= goal {
                streak += 1
            } else {
                break
            }

            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        dailyFocusStreak = streak
        commitMutation()
    }

    func awardBonusXP(_ amount: Int, reason: String = "") {
        award(.init(xp: max(0, amount), skillXP: [], momentum: 0, reason: reason.isEmpty ? "Bonus XP" : reason))
        refreshChallengesAndAchievements()
        commitMutation()
    }

    // Backward compatibility hooks.
    func awardFocus(minutes: Int, logs: [FocusLogEntry], dailyGoal: Int) {
        let entry = FocusLogEntry(id: UUID(), phase: .work, startedAt: Date(), durationSeconds: max(60, minutes * 60), source: "legacy")
        registerFocusSession(entry, dailyGoal: dailyGoal, allLogs: logs + [entry])
    }

    func awardTaskCompletion() {
        let now = Date()
        let task = TaskItem(
            id: UUID(),
            title: "Legacy Task",
            notes: "",
            dueDate: nil,
            priority: .medium,
            difficulty: .medium,
            tags: [],
            status: .done,
            mappedSkills: [.execution],
            isDailyTask: false,
            isRequiredDailyTask: false,
            dailyDateKey: nil,
            recurrence: .none,
            order: 0,
            createdAt: now,
            updatedAt: now,
            completedAt: now
        )
        registerTaskCompletion(task, completedToday: 1)
    }

    func awardHabitCompletion() {
        let habit = HabitItem.makeEmpty()
        registerHabitCompletion(habit, isRequired: false)
    }

    // =====================================================
    // MARK: - Internal Logic
    // [TAG: V2_GAMIFICATION_INTERNAL]
    // =====================================================

    private func award(_ reward: GamificationRewardDefinition, applyMultiplier: Bool = true) {
        var effectiveXP = reward.xp
        if reward.xp > 0, applyMultiplier {
            let multiplier = min(1.18, momentumXPMultiplier * weeklyBonusMultiplier)
            effectiveXP = Int((Double(reward.xp) * multiplier).rounded())
        }

        if effectiveXP != 0 {
            totalXP = max(0, totalXP + effectiveXP)
            season.seasonalXP = max(0, season.seasonalXP + max(0, effectiveXP))
        }

        for (axis, xp) in reward.skillXP {
            applySkillOnly(axis, delta: xp)
        }

        adjustMomentum(reward.momentum)

        xpEntries.insert(
            GamificationXPEntry(
                id: UUID(),
                date: Date(),
                delta: effectiveXP,
                totalXP: totalXP,
                level: currentLevel,
                reason: reward.reason
            ),
            at: 0
        )
        if xpEntries.count > 240 {
            xpEntries = Array(xpEntries.prefix(240))
        }
    }

    private func applySkillOnly(_ axis: GamificationSkillAxis, delta: Int) {
        var state = skills[axis] ?? GamificationSkillState()
        var effective = delta

        if delta > 0 {
            if axis == .focus, specialization.selection == .focusSpecialist {
                effective += Int((Double(delta) * 0.10).rounded())
            }
            if axis == .routine, specialization.selection == .routineSpecialist {
                effective += Int((Double(delta) * 0.10).rounded())
            }
            if axis == .reliability, specialization.selection == .reliabilitySpecialist {
                effective += Int((Double(delta) * 0.10).rounded())
            }
        }

        state.totalXP = max(0, state.totalXP + effective)
        skills[axis] = state
    }

    private func adjustMomentum(_ delta: Int) {
        momentum = min(100, max(0, momentum + delta))
    }

    private var momentumXPMultiplier: Double {
        switch momentum {
        case ..<70: return 1.0
        case 70..<90: return 1.05
        default: return 1.08
        }
    }

    private var weeklyBonusMultiplier: Double {
        guard let until = weeklyXPBonusUntil else { return 1.0 }
        if until < Date() {
            weeklyXPBonusUntil = nil
            weeklyXPBonusMultiplier = 1.0
            return 1.0
        }
        return max(1.0, weeklyXPBonusMultiplier)
    }

    private func applyWeeklyGoalReward() {
        guard weeklyGoal.completed == false else { return }
        weeklyGoal.completed = true

        award(.init(xp: 60, skillXP: [(.reliability, 15)], momentum: 10, reason: "Weekly goal completed"))

        weeklyXPBonusUntil = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        weeklyXPBonusMultiplier = 1.10
    }

    private func refreshChallengesAndAchievements() {
        refreshChallengeProgress(list: &dailyChallenges)
        refreshChallengeProgress(list: &weeklyChallenges)
        refreshChallengeProgress(list: &seasonalChallenges)

        let unlocks = computeAchievementUnlocks()
        for unlock in unlocks {
            achievements.insert(unlock.record, at: 0)
            award(.init(xp: unlock.xpReward, skillXP: [], momentum: 1, reason: "Achievement unlocked"))
        }
    }

    private func refreshChallengeProgress(list: inout [GamificationDailyChallenge]) {
        var pendingRewards: [GamificationRewardDefinition] = []

        for idx in list.indices {
            list[idx].progress = challengeProgress(for: list[idx])
            if list[idx].progress >= list[idx].target {
                list[idx].completed = true
            }

            guard list[idx].completed, list[idx].rewarded == false else { continue }
            list[idx].rewarded = true

            var xp = list[idx].rewardXP
            if specialization.selection == .focusSpecialist,
               list[idx].kind == .focusSessions || list[idx].kind == .weeklyFocusVolume {
                xp += 5
            }

            pendingRewards.append(.init(
                xp: xp,
                skillXP: challengeSkillRewards(for: list[idx]),
                momentum: list[idx].rewardMomentum,
                reason: list[idx].title
            ))

            lastCompletedChallengeID = list[idx].id.uuidString
            challengeCelebrationToken += 1
        }

        for reward in pendingRewards {
            award(reward)
        }
    }

    private func challengeProgress(for challenge: GamificationDailyChallenge) -> Int {
        switch (challenge.cadence, challenge.kind) {
        case (.daily, .focusSessions):
            return min(challenge.target, completedFocusSessionKeys.count)
        case (.daily, .completeTasks):
            return min(challenge.target, completedNormalTaskIDs.count)
        case (.daily, .completeHabits):
            return min(challenge.target, completedHabitKeys.count)
        case (.daily, .completeDailyTasks):
            return min(challenge.target, completedDailyTaskIDs.count)
        case (.daily, .dailyPackCompletion):
            let today = Self.dayKey(Date())
            let count = rewardedDailyPackKeys.filter { $0.hasPrefix("\(today)-pack:") }.count
            return min(challenge.target, count)
        case (.weekly, .weeklyConsistency), (.weekly, .completeDailyTasks):
            return min(challenge.target, weeklyDailyCompletionDayKeys.count)
        case (.weekly, .weeklyFocusVolume):
            return min(challenge.target, weeklyFocusSessions)
        case (.weekly, .perfectDay), (.daily, .perfectDay):
            let weekKey = Self.weekKey(Date())
            let weekPerfect = perfectDayKeys.filter { key in
                guard let date = Self.dateFromDayKey(key) else { return false }
                return Self.weekKey(date) == weekKey
            }.count
            return min(challenge.target, challenge.cadence == .weekly ? weekPerfect : (perfectDayKeys.contains(Self.dayKey(Date())) ? 1 : 0))
        case (.seasonal, .seasonalMomentum):
            return min(challenge.target, season.stats.perfectDays)
        case (_, .recoveryWalk), (_, .recoveryClean), (_, .recoveryReflect):
            return recoveryChallenge?.completed == true ? challenge.target : 0
        default:
            return 0
        }
    }

    private func challengeSkillRewards(for challenge: GamificationDailyChallenge) -> [(GamificationSkillAxis, Int)] {
        switch (challenge.cadence, challenge.kind) {
        case (_, .earlyWin),
             (_, .consistency),
             (_, .taskSprint),
             (_, .habitCombo),
             (_, .cleanInbox),
             (_, .deepFocus),
             (_, .studySession):
            return [(.execution, 6)]
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

    private func computeAchievementUnlocks() -> [GamificationAchievementUnlock] {
        let existing = Set(achievements.map(\.title))
        var unlocks: [GamificationAchievementUnlock] = []

        func append(
            _ title: String,
            detail: String,
            icon: String,
            tier: String,
            xp: Int,
            hidden: Bool = false,
            rewardTitle: String? = nil,
            rewardCosmetic: String? = nil
        ) {
            guard existing.contains(title) == false else { return }
            unlocks.append(
                .init(
                    record: .init(
                        id: UUID(),
                        title: title,
                        detail: detail,
                        icon: icon,
                        unlockedAt: Date(),
                        tier: tier,
                        hidden: hidden,
                        rewardTitle: rewardTitle,
                        rewardCosmetic: rewardCosmetic
                    ),
                    xpReward: xp
                )
            )
        }

        if totalXP >= 100 {
            append("First 100 XP", detail: "Reach your first major progression checkpoint.", icon: "sparkles", tier: "small", xp: 20, rewardTitle: "Starter")
        }
        if totalXP >= 1000 {
            append("Level Momentum", detail: "Accumulate 1000 total XP.", icon: "bolt.fill", tier: "medium", xp: 40, rewardCosmetic: "pulse-ring")
        }
        if perfectDayKeys.count >= 7 {
            append("Perfect Seven", detail: "Achieve 7 perfect days.", icon: "star.circle.fill", tier: "large", xp: 75, rewardTitle: "Flawless")
        }
        if lifetimeFocusSessions >= 30 {
            append("Focus Adept", detail: "Complete 30 focus sessions.", icon: "timer", tier: "medium", xp: 40, rewardTitle: "Session Adept")
        }
        if lifetimeTaskCompletions >= 100 {
            append("Execution Centurion", detail: "Complete 100 normal tasks.", icon: "checkmark.seal.fill", tier: "large", xp: 75, rewardCosmetic: "task-halo")
        }
        if lifetimeRequiredHabitCompletions >= 30 {
            append("Reliable Core", detail: "Complete 30 required habits.", icon: "shield.lefthalf.filled", tier: "medium", xp: 40, rewardTitle: "Reliable")
        }
        if lifetimeDailyCompletionDays >= 14 {
            append("Daily Commander", detail: "Finish all daily tasks on 14 days.", icon: "calendar.badge.checkmark", tier: "large", xp: 75, rewardTitle: "Commander")
        }
        if momentum >= 95 {
            append("Hidden: Peak Form", detail: "Reach momentum 95+.", icon: "flame.fill", tier: "small", xp: 20, hidden: true, rewardCosmetic: "ember")
        }

        return unlocks
    }

    private func rewardAllDailyCompletion(dayKey: String) {
        let key = "\(dayKey)-all"
        guard rewardedDailyCompletionDayKeys.contains(key) == false else { return }
        rewardedDailyCompletionDayKeys.append(key)

        if weeklyDailyCompletionDayKeys.contains(dayKey) == false {
            weeklyDailyCompletionDayKeys.append(dayKey)
            weeklyGoal.completedDailyCompletions += 1
            lifetimeDailyCompletionDays += 1
        }

        var xp = 25
        if specialization.selection == .reliabilitySpecialist {
            xp += 10
        }

        award(.init(xp: xp, skillXP: [(.reliability, 12)], momentum: 8, reason: "All daily tasks completed"))
    }

    private func rewardCompletedDailyPacks(dayKey: String, dailyTasks: [TaskItem]) {
        let packTags = Set(dailyTasks.flatMap { task in
            task.tags.filter { $0.hasPrefix("pack:") }
        })

        for tag in packTags {
            let key = "\(dayKey)-\(tag)"
            guard rewardedDailyPackKeys.contains(key) == false else { continue }

            let packTasks = dailyTasks.filter { $0.tags.contains(tag) }
            guard packTasks.isEmpty == false, packTasks.allSatisfy({ $0.status == .done }) else { continue }

            rewardedDailyPackKeys.append(key)
            award(.init(xp: 10, skillXP: [(.reliability, 4)], momentum: 2, reason: "Daily task pack completed"))
        }
    }

    private func settlePendingRecoveryIfNeeded(evaluatingDayKey: String) {
        guard let pendingRecovery else { return }
        guard pendingRecovery.dayKey != evaluatingDayKey else { return }

        if recoveryChallenge?.completed == true {
            let reducedXP = -3 * pendingRecovery.missedCount
            let tinyMomentum = -min(2, pendingRecovery.missedCount)
            award(.init(xp: reducedXP, skillXP: [], momentum: tinyMomentum, reason: "Recovery challenge completed"), applyMultiplier: false)
        } else {
            let fullXP = -10 * pendingRecovery.missedCount
            let fullReliability = -5 * pendingRecovery.missedCount
            let momentumLoss = -8 * pendingRecovery.missedCount
            award(.init(xp: fullXP, skillXP: [(.reliability, fullReliability)], momentum: momentumLoss, reason: "Missed daily tasks"), applyMultiplier: false)
        }

        self.pendingRecovery = nil
        self.recoveryChallenge = nil
    }

    private func trackResetProgress(focusDelta: Int, taskDelta: Int, habitDelta: Int) {
        guard resetDayChallenge.isActive else { return }

        resetDayChallenge.focusProgress = min(resetDayChallenge.focusTarget, resetDayChallenge.focusProgress + focusDelta)
        resetDayChallenge.taskProgress = min(resetDayChallenge.taskTarget, resetDayChallenge.taskProgress + taskDelta)
        resetDayChallenge.habitProgress = min(resetDayChallenge.habitTarget, resetDayChallenge.habitProgress + habitDelta)

        guard resetDayChallenge.isCompleted else { return }

        momentum = 50
        badDayStreak = 0
        pendingRecovery = nil
        recoveryChallenge = nil
        resetDayUsedWeekKey = Self.weekKey(Date())
        resetDayChallenge.isActive = false
        resetDayChallenge.focusProgress = resetDayChallenge.focusTarget
        resetDayChallenge.taskProgress = resetDayChallenge.taskTarget
        resetDayChallenge.habitProgress = resetDayChallenge.habitTarget
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
        if specialization.selection == .routineSpecialist {
            return Int((Double(base) * 1.2).rounded())
        }
        return base
    }

    private func awardComboIfNeeded(dayKey: String, completedToday: Int) {
        let combos: [(Int, Int, Int)] = [
            (3, 8, 2),
            (5, 15, 3),
            (8, 25, 5)
        ]

        for (threshold, baseXP, momentumGain) in combos where completedToday == threshold {
            let key = "\(dayKey)-combo-\(threshold)"
            guard rewardedComboKeys.contains(key) == false else { continue }
            rewardedComboKeys.append(key)

            var comboXP = baseXP
            if specialization.selection == .executionSpecialist {
                comboXP += 5
            }

            award(.init(xp: comboXP, skillXP: [], momentum: momentumGain, reason: "\(threshold)-task combo"))
        }
    }

    private func commitMutation() {
        lastModifiedAt = Date()
        persist()
    }

    private func ensureDailyState(now: Date) {
        let dayKey = Self.dayKey(now)
        if dailyChallenges.first?.dayKey != dayKey {
            dailyChallenges = Self.generateDailyChallenges(for: dayKey, focusLevel: skills[.focus]?.skillLevel ?? 1, executionLevel: skills[.execution]?.skillLevel ?? 1, reliabilityLevel: skills[.reliability]?.skillLevel ?? 1)
            completedDailyTaskIDs = []
            completedNormalTaskIDs = []
            completedHabitKeys = []
            completedFocusSessionKeys = []
            overduePenaltyByDay = [:]
        }

        let weekKey = Self.weekKey(now)
        if weeklyGoal.weekKey != weekKey {
            weeklyGoal = .init(weekKey: weekKey, requiredDailyCompletions: 5, completedDailyCompletions: 0, completed: false)
            weeklyChallenges = Self.generateWeeklyChallenges(for: weekKey, weeklyFocusSessions: weeklyFocusSessions)
            weeklyDailyCompletionDayKeys = []
            weeklyFocusSessions = 0
            weeklyTaskCompletions = 0
            weeklyHabitCompletions = 0
            weeklyPerfectDays = 0
            if resetDayChallenge.weekKey != weekKey {
                resetDayChallenge = .empty(weekKey: weekKey)
            }
        }

        if now > season.endDate {
            season = Self.currentSeason(now: now)
            seasonalChallenges = Self.generateSeasonalChallenges(for: season)
        } else if seasonalChallenges.isEmpty {
            seasonalChallenges = Self.generateSeasonalChallenges(for: season)
        }
    }

    private func applyCloudGameState(_ state: CloudGameState, modifiedAt: Date) {
        totalXP = max(0, state.totalXP)
        momentum = min(100, max(0, state.momentum))

        skills = [
            .focus: .init(totalXP: max(0, state.skills.focus.xp)),
            .execution: .init(totalXP: max(0, state.skills.execution.xp)),
            .routine: .init(totalXP: max(0, state.skills.routine.xp)),
            .reliability: .init(totalXP: max(0, state.skills.reliability.xp))
        ]

        dailyChallenges = state.dailyChallenges
        weeklyChallenges = state.weeklyChallenges
        seasonalChallenges = state.seasonalChallenges
        recoveryChallenge = state.recoveryChallenge
        pendingRecovery = state.pendingRecovery

        weeklyGoal = state.weeklyGoal
        specialization = state.specialization
        season = state.season

        achievements = state.achievements
        xpEntries = state.xpEntries

        completedDailyTaskIDs = state.completedDailyTaskIDs
        completedNormalTaskIDs = state.completedNormalTaskIDs
        completedHabitKeys = state.completedHabitKeys
        completedFocusSessionKeys = state.completedFocusSessionKeys
        perfectDayKeys = state.perfectDayKeys

        rewardedFocusThreeSessionDayKeys = state.rewardedFocusThreeSessionDayKeys
        rewardedFocusGoalDayKeys = state.rewardedFocusGoalDayKeys
        rewardedComboKeys = state.rewardedComboKeys
        rewardedDailyCompletionDayKeys = state.rewardedDailyCompletionDayKeys
        rewardedDailyPackKeys = state.rewardedDailyPackKeys
        rewardedMilestoneKeys = state.rewardedMilestoneKeys

        weeklyDailyCompletionDayKeys = state.weeklyDailyCompletionDayKeys
        weeklyFocusSessions = state.weeklyFocusSessions
        weeklyTaskCompletions = state.weeklyTaskCompletions
        weeklyHabitCompletions = state.weeklyHabitCompletions
        weeklyPerfectDays = state.weeklyPerfectDays

        lifetimeFocusSessions = state.lifetimeFocusSessions
        lifetimeTaskCompletions = state.lifetimeTaskCompletions
        lifetimeHabitCompletions = state.lifetimeHabitCompletions
        lifetimeRequiredHabitCompletions = state.lifetimeRequiredHabitCompletions
        lifetimeDailyCompletionDays = state.lifetimeDailyCompletionDays

        badDayStreak = state.badDayStreak
        resetDayUsedWeekKey = state.resetDayUsedWeekKey
        resetDayChallenge = state.resetDayChallenge

        weeklyXPBonusUntil = state.weeklyXPBonusUntil
        weeklyXPBonusMultiplier = state.weeklyXPBonusMultiplier

        overduePenaltyByDay = state.overduePenaltyByDay

        lastEvaluatedDayKey = state.lastEvaluatedDayKey
        lastSummaryDayKey = state.lastSummaryDayKey
        lastModifiedAt = max(modifiedAt, state.lastModifiedAt)
    }

    private func preferredPack() -> String {
        let focusLevel = skills[.focus]?.skillLevel ?? 1
        let executionLevel = skills[.execution]?.skillLevel ?? 1
        let routineLevel = skills[.routine]?.skillLevel ?? 1
        let reliabilityLevel = skills[.reliability]?.skillLevel ?? 1

        if reliabilityLevel <= executionLevel { return "discipline" }
        if routineLevel < focusLevel { return "routine" }
        if momentum < 45 { return "reset" }
        if executionLevel >= focusLevel + 2 { return "student" }
        return "productivity"
    }

    private static func makeRecoveryChallenge(severity: Int, sourceTaskID: UUID?) -> GamificationRecoveryChallenge {
        let safe = max(1, min(3, severity))
        switch safe {
        case 1:
            return GamificationRecoveryChallenge(
                id: UUID(),
                title: "Recovery Reflection",
                detail: "Write 3 short lines about what blocked you.",
                category: .reflection,
                severity: safe,
                completed: false,
                expiresAt: Date().addingTimeInterval(8 * 60 * 60),
                sourceTaskID: sourceTaskID
            )
        case 2:
            return GamificationRecoveryChallenge(
                id: UUID(),
                title: "Recovery Reset",
                detail: "Tidy your desk or room for 5 minutes.",
                category: .cleaning,
                severity: safe,
                completed: false,
                expiresAt: Date().addingTimeInterval(8 * 60 * 60),
                sourceTaskID: sourceTaskID
            )
        default:
            return GamificationRecoveryChallenge(
                id: UUID(),
                title: "Recovery Movement",
                detail: "Take a short walk or complete 20 squats.",
                category: .physical,
                severity: safe,
                completed: false,
                expiresAt: Date().addingTimeInterval(8 * 60 * 60),
                sourceTaskID: sourceTaskID
            )
        }
    }

    private func appendFirstAvailable(
        into templates: inout [TaskItem],
        seenTitles: inout Set<String>,
        candidates: [TaskItem]
    ) {
        guard let candidate = candidates.first(where: { seenTitles.contains($0.title.lowercased()) == false }) else { return }
        seenTitles.insert(candidate.title.lowercased())
        templates.append(candidate)
    }

    private static func generateDailyChallenges(
        for dayKey: String,
        focusLevel: Int,
        executionLevel: Int,
        reliabilityLevel: Int
    ) -> [GamificationDailyChallenge] {
        let highFocus = focusLevel > executionLevel + 1
        let lowReliability = reliabilityLevel < 5

        return [
            GamificationDailyChallenge(
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
            ),
            GamificationDailyChallenge(
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
            ),
            GamificationDailyChallenge(
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
        ]
    }

    private static func generateWeeklyChallenges(for weekKey: String, weeklyFocusSessions: Int) -> [GamificationDailyChallenge] {
        let hardFocusTarget = max(8, min(14, weeklyFocusSessions + 8))
        return [
            GamificationDailyChallenge(
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
            ),
            GamificationDailyChallenge(
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
        ]
    }

    private static func generateSeasonalChallenges(for season: GamificationSeasonState) -> [GamificationDailyChallenge] {
        [
            GamificationDailyChallenge(
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

    private var stateFileURL: URL {
        fileURL
    }

    private func persist() {
        ensureDirectory()
        guard let data = try? encoder.encode(cloudSnapshot()) else { return }
        try? data.write(to: stateFileURL, options: .atomic)
    }

    private func load() {
        ensureDirectory()
        guard let data = try? Data(contentsOf: stateFileURL) else { return }

        if let snapshot = try? decoder.decode(CloudSnapshot.self, from: data) {
            applyCloudGameState(snapshot.game, modifiedAt: snapshot.modifiedAt)
            return
        }

        if let legacy = try? decoder.decode(LegacyStore.self, from: data) {
            migrateFromLegacy(legacy)
        }
    }

    private func ensureDirectory() {
        let directory = JSONStorageService.baseDirectory
        if FileManager.default.fileExists(atPath: directory.path) == false {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // =====================================================
    // MARK: - Legacy Migration
    // [TAG: V2_GAMIFICATION_MIGRATION]
    // =====================================================

    private struct LegacyStore: Codable {
        var totalXP: Int
        var dailyFocusStreak: Int
        var skillTotalXP: [String: Int]
    }

    private func migrateFromLegacy(_ legacy: LegacyStore) {
        totalXP = max(0, legacy.totalXP)
        dailyFocusStreak = max(0, legacy.dailyFocusStreak)

        let focusXP = max(0, legacy.skillTotalXP["focus"] ?? 0)
        let consistencyXP = max(0, legacy.skillTotalXP["consistency"] ?? 0)
        let disciplineXP = max(0, legacy.skillTotalXP["discipline"] ?? 0)
        let planningXP = max(0, legacy.skillTotalXP["planning"] ?? 0)
        let healthXP = max(0, legacy.skillTotalXP["health"] ?? 0)
        let learningXP = max(0, legacy.skillTotalXP["learning"] ?? 0)

        skills[.focus] = .init(totalXP: focusXP)
        skills[.execution] = .init(totalXP: disciplineXP + planningXP)
        skills[.routine] = .init(totalXP: consistencyXP + (healthXP / 2))
        skills[.reliability] = .init(totalXP: (consistencyXP / 2) + (planningXP / 2) + (learningXP / 2))

        momentum = 50
        achievements = []
        xpEntries = []
        weeklyGoal = .init(weekKey: Self.weekKey(Date()), requiredDailyCompletions: 5, completedDailyCompletions: 0, completed: false)
        season = Self.currentSeason(now: Date())
        specialization = .init(selection: .none, lastChangedAt: nil)

        completedDailyTaskIDs = []
        completedNormalTaskIDs = []
        completedHabitKeys = []
        completedFocusSessionKeys = []
        perfectDayKeys = []

        rewardedFocusThreeSessionDayKeys = []
        rewardedFocusGoalDayKeys = []
        rewardedComboKeys = []
        rewardedDailyCompletionDayKeys = []
        rewardedDailyPackKeys = []
        rewardedMilestoneKeys = []

        pendingRecovery = nil
        weeklyDailyCompletionDayKeys = []
        weeklyFocusSessions = 0
        weeklyTaskCompletions = 0
        weeklyHabitCompletions = 0
        weeklyPerfectDays = 0

        lifetimeFocusSessions = 0
        lifetimeTaskCompletions = 0
        lifetimeHabitCompletions = 0
        lifetimeRequiredHabitCompletions = 0
        lifetimeDailyCompletionDays = 0

        badDayStreak = 0
        resetDayUsedWeekKey = nil
        resetDayChallenge = .empty(weekKey: Self.weekKey(Date()))

        weeklyXPBonusUntil = nil
        weeklyXPBonusMultiplier = 1.0
        overduePenaltyByDay = [:]

        lastEvaluatedDayKey = nil
        lastSummaryDayKey = nil
        lastModifiedAt = Date()
    }

    // =====================================================
    // MARK: - XP Curve
    // [TAG: V2_GAMIFICATION_LEVEL_CURVE]
    // =====================================================

    private static func xpNeededForNextLevel(level: Int) -> Int {
        let safe = max(1, level)
        let step = safe - 1
        return 100 + (step * 35) + (step * step * 5)
    }

    private static func totalXPRequired(toReach level: Int) -> Int {
        guard level > 1 else { return 0 }
        var total = 0
        for idx in 1..<level {
            total += xpNeededForNextLevel(level: idx)
        }
        return total
    }

    private static func level(forXP xp: Int) -> Int {
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
            if level > 1000 {
                return level
            }
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func weekKey(_ date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
    }

    private static func dateFromDayKey(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    private static func currentSeason(now: Date) -> GamificationSeasonState {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: now)
        let year = comps.year ?? 2026
        let month = comps.month ?? 1
        let startMonth = ((max(1, month) - 1) / 3) * 3 + 1

        var startComp = DateComponents()
        startComp.year = year
        startComp.month = startMonth
        startComp.day = 1

        let startDate = calendar.date(from: startComp) ?? now
        let endDate = calendar.date(byAdding: .month, value: 3, to: startDate)?.addingTimeInterval(-1) ?? now

        return GamificationSeasonState(
            id: UUID(),
            title: "Season \(year).\(startMonth)",
            startDate: startDate,
            endDate: endDate,
            seasonalXP: 0,
            badgeUnlocked: false,
            unlockedTitles: [],
            unlockedPackIDs: ["productivity"],
            stats: .zero
        )
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
        return "\(dayKey): \(dailyStatus), \(focusStatus), \(habitStatus), \(perfect). Momentum \(momentum)."
    }

    private func currentHabitStreak(_ habit: HabitItem) -> Int {
        var streak = 0
        var cursor = Calendar.current.startOfDay(for: Date())
        while true {
            let key = Self.dayKey(cursor)
            if habit.history[key, default: 0] >= habit.targetPerDay {
                streak += 1
            } else {
                break
            }
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private func mapTaskSkill(_ tag: TaskSkillTag) -> GamificationSkillAxis {
        switch tag {
        case .focus: return .focus
        case .execution: return .execution
        case .routine: return .routine
        case .reliability: return .reliability
        }
    }

    private func isOverdueCompletion(_ task: TaskItem) -> Bool {
        guard let due = task.dueDate else { return false }
        let completedAt = task.completedAt ?? Date()
        return completedAt > due
    }
}

private extension TaskItem {
    var priorityBonus: Int {
        switch priority {
        case .low: return 0
        case .medium: return 2
        case .high: return 4
        }
    }
}
