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
    case consistency
    case discipline
    case planning
    case health
    case learning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Focus"
        case .consistency: return "Consistency"
        case .discipline: return "Discipline"
        case .planning: return "Planning"
        case .health: return "Health"
        case .learning: return "Learning"
        }
    }
}

struct GamificationSkillState: Codable, Equatable {
    var totalXP: Int = 0

    var skillLevel: Int {
        min(20, max(1, (totalXP / 100) + 1))
    }

    var skillXP: Int {
        totalXP % 100
    }

    var skillProgress0to1: Double {
        Double(skillXP) / 100.0
    }

    var normalized0to1: Double {
        Double(skillLevel) / 20.0
    }
}

// =====================================================
// MARK: - Achievement
// [TAG: V2_GAMIFICATION_ACHIEVEMENT]
// =====================================================

enum GamificationAchievement: String, Codable, CaseIterable, Identifiable {
    case firstFocusSession
    case first100XP
    case sevenDayFocusStreak
    case tenTasksCompleted
    case tenHabitsCompleted
    case level10Reached

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstFocusSession: return "First Focus Session"
        case .first100XP: return "First 100 XP"
        case .sevenDayFocusStreak: return "7-Day Focus Streak"
        case .tenTasksCompleted: return "10 Tasks Completed"
        case .tenHabitsCompleted: return "10 Habits Completed"
        case .level10Reached: return "Level 10 Reached"
        }
    }

    var description: String {
        switch self {
        case .firstFocusSession: return "Complete your first focus session."
        case .first100XP: return "Reach 100 total XP."
        case .sevenDayFocusStreak: return "Hit your daily focus goal for 7 days in a row."
        case .tenTasksCompleted: return "Complete 10 tasks."
        case .tenHabitsCompleted: return "Complete 10 habits."
        case .level10Reached: return "Reach global level 10."
        }
    }
}

// =====================================================
// MARK: - Daily Challenge
// [TAG: V2_GAMIFICATION_CHALLENGE]
// =====================================================

enum GamificationChallengeKind: String, Codable, CaseIterable {
    case deepFocus
    case taskSprint
    case earlyWin
    case habitCombo
    case consistency
    case cleanInbox
    case studySession
}

struct GamificationDailyChallenge: Identifiable, Codable, Equatable {
    var id: String
    var kind: GamificationChallengeKind
    var title: String
    var description: String
    var rewardXP: Int
    var progress: Int
    var target: Int
    var completed: Bool
    var rewarded: Bool
}

// =====================================================
// MARK: - Storage Model
// [TAG: V2_GAMIFICATION_STORAGE]
// =====================================================

private struct GamificationDailyMetrics: Codable {
    var dayKey: String
    var focusMinutes: Int
    var tasksCompleted: Int
    var habitsCompleted: Int
    var highPriorityBeforeNoon: Int
    var learningFocusMinutes: Int
    var reachedDailyGoal: Bool

    static func empty(dayKey: String) -> GamificationDailyMetrics {
        GamificationDailyMetrics(
            dayKey: dayKey,
            focusMinutes: 0,
            tasksCompleted: 0,
            habitsCompleted: 0,
            highPriorityBeforeNoon: 0,
            learningFocusMinutes: 0,
            reachedDailyGoal: false
        )
    }
}

private struct GamificationStore: Codable {
    var totalXP: Int
    var dailyFocusStreak: Int
    var skillPoints: Int
    var totalFocusSessions: Int
    var totalTasksCompleted: Int
    var totalHabitsCompleted: Int

    var skillTotalXP: [String: Int]
    var achievementUnlocks: [String: Date]

    var dailyMetrics: GamificationDailyMetrics
    var dailySkillGain: [String: Int]
    var dailyChallenges: [GamificationDailyChallenge]

    var legacyUnlockedAchievements: [GamificationAchievement]?

    enum CodingKeys: String, CodingKey {
        case totalXP
        case dailyFocusStreak
        case skillPoints
        case totalFocusSessions
        case totalTasksCompleted
        case totalHabitsCompleted
        case skillTotalXP
        case achievementUnlocks
        case dailyMetrics
        case dailySkillGain
        case dailyChallenges
        case legacyUnlockedAchievements = "unlockedAchievements"
    }

    init(
        totalXP: Int,
        dailyFocusStreak: Int,
        skillPoints: Int,
        totalFocusSessions: Int,
        totalTasksCompleted: Int,
        totalHabitsCompleted: Int,
        skillTotalXP: [String: Int],
        achievementUnlocks: [String: Date],
        dailyMetrics: GamificationDailyMetrics,
        dailySkillGain: [String: Int],
        dailyChallenges: [GamificationDailyChallenge],
        legacyUnlockedAchievements: [GamificationAchievement]? = nil
    ) {
        self.totalXP = totalXP
        self.dailyFocusStreak = dailyFocusStreak
        self.skillPoints = skillPoints
        self.totalFocusSessions = totalFocusSessions
        self.totalTasksCompleted = totalTasksCompleted
        self.totalHabitsCompleted = totalHabitsCompleted
        self.skillTotalXP = skillTotalXP
        self.achievementUnlocks = achievementUnlocks
        self.dailyMetrics = dailyMetrics
        self.dailySkillGain = dailySkillGain
        self.dailyChallenges = dailyChallenges
        self.legacyUnlockedAchievements = legacyUnlockedAchievements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        totalXP = try container.decodeIfPresent(Int.self, forKey: .totalXP) ?? 0
        dailyFocusStreak = try container.decodeIfPresent(Int.self, forKey: .dailyFocusStreak) ?? 0
        skillPoints = try container.decodeIfPresent(Int.self, forKey: .skillPoints) ?? 0
        totalFocusSessions = try container.decodeIfPresent(Int.self, forKey: .totalFocusSessions) ?? 0
        totalTasksCompleted = try container.decodeIfPresent(Int.self, forKey: .totalTasksCompleted) ?? 0
        totalHabitsCompleted = try container.decodeIfPresent(Int.self, forKey: .totalHabitsCompleted) ?? 0

        skillTotalXP = try container.decodeIfPresent([String: Int].self, forKey: .skillTotalXP) ?? [:]
        achievementUnlocks = try container.decodeIfPresent([String: Date].self, forKey: .achievementUnlocks) ?? [:]

        let fallbackMetrics = GamificationDailyMetrics.empty(dayKey: "")
        dailyMetrics = try container.decodeIfPresent(GamificationDailyMetrics.self, forKey: .dailyMetrics) ?? fallbackMetrics
        dailySkillGain = try container.decodeIfPresent([String: Int].self, forKey: .dailySkillGain) ?? [:]
        dailyChallenges = try container.decodeIfPresent([GamificationDailyChallenge].self, forKey: .dailyChallenges) ?? []

        legacyUnlockedAchievements = try container.decodeIfPresent([GamificationAchievement].self, forKey: .legacyUnlockedAchievements)
    }
}

private struct GamificationChallengeTemplate {
    let kind: GamificationChallengeKind
    let title: String
    let description: String
    let target: Int
    let rewardXP: Int
}

// =====================================================
// MARK: - Service
// [TAG: V2_GAMIFICATION_SERVICE]
// =====================================================

@MainActor
final class GamificationService: ObservableObject {
    @Published private(set) var totalXP: Int = 0
    @Published private(set) var dailyFocusStreak: Int = 0
    @Published private(set) var skillPoints: Int = 0

    @Published private(set) var skills: [GamificationSkillAxis: GamificationSkillState] = [:]
    @Published private(set) var dailyChallenges: [GamificationDailyChallenge] = []

    @Published private(set) var lastCompletedChallengeID: String?
    @Published private(set) var challengeCelebrationToken: Int = 0

    var personalizedChallengeProvider: ((String, [GamificationDailyChallenge]) async -> [GamificationDailyChallenge]?)?

    private var achievementUnlocks: [GamificationAchievement: Date] = [:]

    private var totalFocusSessions = 0
    private var totalTasksCompleted = 0
    private var totalHabitsCompleted = 0

    private var dailyMetrics: GamificationDailyMetrics = .empty(dayKey: "")
    private var dailySkillGain: [GamificationSkillAxis: Int] = [:]

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileURL: URL

    private var dayTicker: AnyCancellable?
    private var challengePersonalizationTask: Task<Void, Never>?

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        fileURL = JSONStorageService.baseDirectory.appendingPathComponent("gamification.json")

        skills = Dictionary(uniqueKeysWithValues: GamificationSkillAxis.allCases.map { ($0, GamificationSkillState()) })

        load()
        ensureCurrentDay()
        refreshAchievements()
        refreshChallengesAndRewards()
        persist()

        dayTicker = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.ensureCurrentDay()
            }
    }

    deinit {
        dayTicker?.cancel()
        challengePersonalizationTask?.cancel()
    }

    // =====================================================
    // MARK: - Public Derived State
    // =====================================================

    var currentLevel: Int {
        max(1, (totalXP / 100) + 1)
    }

    var xpInLevel: Int {
        totalXP % 100
    }

    var xpToNextLevel: Int {
        max(0, 100 - xpInLevel)
    }

    var progress0to1: Double {
        Double(xpInLevel) / 100.0
    }

    var level: Int {
        currentLevel
    }

    var progressToNextLevel: Double {
        progress0to1
    }

    var unlockedAchievements: [GamificationAchievement] {
        GamificationAchievement.allCases.filter { achievementUnlocks[$0] != nil }
    }

    func unlockedAt(for achievement: GamificationAchievement) -> Date? {
        achievementUnlocks[achievement]
    }

    // =====================================================
    // MARK: - Cloud Snapshot
    // [TAG: V2_GAMIFICATION_CLOUD_SYNC]
    // =====================================================

    struct CloudSnapshot: Codable, Equatable {
        var totalXP: Int
        var dailyFocusStreak: Int
        var skillPoints: Int
        var totalFocusSessions: Int
        var totalTasksCompleted: Int
        var totalHabitsCompleted: Int
        var skills: [String: Int]
        var achievementUnlocks: [String: Date]
        var dailyMetrics: CloudDailyMetrics
        var dailySkillGain: [String: Int]
        var dailyChallenges: [GamificationDailyChallenge]
    }

    struct CloudDailyMetrics: Codable, Equatable {
        var dayKey: String
        var focusMinutes: Int
        var tasksCompleted: Int
        var habitsCompleted: Int
        var highPriorityBeforeNoon: Int
        var learningFocusMinutes: Int
        var reachedDailyGoal: Bool
    }

    func cloudSnapshot() -> CloudSnapshot {
        CloudSnapshot(
            totalXP: totalXP,
            dailyFocusStreak: dailyFocusStreak,
            skillPoints: skillPoints,
            totalFocusSessions: totalFocusSessions,
            totalTasksCompleted: totalTasksCompleted,
            totalHabitsCompleted: totalHabitsCompleted,
            skills: Dictionary(uniqueKeysWithValues: skills.map { ($0.key.rawValue, $0.value.totalXP) }),
            achievementUnlocks: Dictionary(uniqueKeysWithValues: achievementUnlocks.map { ($0.key.rawValue, $0.value) }),
            dailyMetrics: CloudDailyMetrics(
                dayKey: dailyMetrics.dayKey,
                focusMinutes: dailyMetrics.focusMinutes,
                tasksCompleted: dailyMetrics.tasksCompleted,
                habitsCompleted: dailyMetrics.habitsCompleted,
                highPriorityBeforeNoon: dailyMetrics.highPriorityBeforeNoon,
                learningFocusMinutes: dailyMetrics.learningFocusMinutes,
                reachedDailyGoal: dailyMetrics.reachedDailyGoal
            ),
            dailySkillGain: Dictionary(uniqueKeysWithValues: dailySkillGain.map { ($0.key.rawValue, $0.value) }),
            dailyChallenges: dailyChallenges
        )
    }

    func applyCloudSnapshot(_ snapshot: CloudSnapshot) {
        totalXP = max(0, snapshot.totalXP)
        dailyFocusStreak = max(0, snapshot.dailyFocusStreak)
        skillPoints = max(0, snapshot.skillPoints)
        totalFocusSessions = max(0, snapshot.totalFocusSessions)
        totalTasksCompleted = max(0, snapshot.totalTasksCompleted)
        totalHabitsCompleted = max(0, snapshot.totalHabitsCompleted)

        var mappedSkills: [GamificationSkillAxis: GamificationSkillState] = [:]
        for axis in GamificationSkillAxis.allCases {
            let value = max(0, snapshot.skills[axis.rawValue] ?? 0)
            mappedSkills[axis] = GamificationSkillState(totalXP: value)
        }
        skills = mappedSkills

        var mappedUnlocks: [GamificationAchievement: Date] = [:]
        for (key, value) in snapshot.achievementUnlocks {
            guard let achievement = GamificationAchievement(rawValue: key) else { continue }
            mappedUnlocks[achievement] = value
        }
        achievementUnlocks = mappedUnlocks

        dailyMetrics = GamificationDailyMetrics(
            dayKey: snapshot.dailyMetrics.dayKey,
            focusMinutes: max(0, snapshot.dailyMetrics.focusMinutes),
            tasksCompleted: max(0, snapshot.dailyMetrics.tasksCompleted),
            habitsCompleted: max(0, snapshot.dailyMetrics.habitsCompleted),
            highPriorityBeforeNoon: max(0, snapshot.dailyMetrics.highPriorityBeforeNoon),
            learningFocusMinutes: max(0, snapshot.dailyMetrics.learningFocusMinutes),
            reachedDailyGoal: snapshot.dailyMetrics.reachedDailyGoal
        )

        var mappedDailyGain: [GamificationSkillAxis: Int] = [:]
        for (key, value) in snapshot.dailySkillGain {
            guard let axis = GamificationSkillAxis(rawValue: key) else { continue }
            mappedDailyGain[axis] = max(0, value)
        }
        dailySkillGain = mappedDailyGain

        dailyChallenges = snapshot.dailyChallenges
        refreshAchievements()
        refreshChallengesAndRewards()
        persist()
    }

    // =====================================================
    // MARK: - Integration Hooks
    // =====================================================

    func registerFocusSession(_ entry: FocusLogEntry, dailyGoal: Int, allLogs: [FocusLogEntry]) {
        ensureCurrentDay()

        let minutes = max(1, entry.durationSeconds / 60)
        grantXP(minutes)
        totalFocusSessions += 1

        dailyMetrics.focusMinutes += minutes

        addSkillXP(.focus, amount: minutes)

        if isLearningSource(entry.source) {
            dailyMetrics.learningFocusMinutes += minutes
            addSkillXP(.learning, amount: max(6, minutes / 2))
        }

        updateFocusStreak(from: allLogs, dailyGoal: dailyGoal, awardConsistency: true)
        if dailyMetrics.reachedDailyGoal {
            addSkillXP(.consistency, amount: 6)
        }

        refreshChallengesAndRewards()
        refreshAchievements()
        persist()
    }

    func registerTaskCompletion(_ task: TaskItem) {
        ensureCurrentDay()

        grantXP(5)
        totalTasksCompleted += 1
        dailyMetrics.tasksCompleted += 1

        addSkillXP(.planning, amount: 5)

        let completedAt = task.completedAt ?? Date()
        if let dueDate = task.dueDate {
            let dueCutoff = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: dueDate) ?? dueDate

            if task.priority == .high {
                if completedAt <= dueCutoff {
                    addSkillXP(.discipline, amount: 24)
                    if Calendar.current.component(.hour, from: completedAt) < 12 {
                        dailyMetrics.highPriorityBeforeNoon += 1
                    }
                } else {
                    addSkillXP(.discipline, amount: 5)
                }
            }

            let leadDays = Calendar.current.dateComponents([.day], from: task.createdAt, to: dueDate).day ?? 0
            if leadDays >= 1, leadDays <= 45, completedAt <= dueCutoff {
                addSkillXP(.planning, amount: 16)
            }
        }

        refreshChallengesAndRewards()
        refreshAchievements()
        persist()
    }

    func registerHabitCompletion(_ habit: HabitItem) {
        ensureCurrentDay()

        grantXP(10)
        totalHabitsCompleted += 1
        dailyMetrics.habitsCompleted += 1

        addSkillXP(.consistency, amount: 8)

        let tags = normalizedTokens(habit.tags + [habit.title])
        if tags.contains("health") {
            addSkillXP(.health, amount: 20)
        }

        if tags.contains("learning") || tags.contains("study") {
            addSkillXP(.learning, amount: 20)
        }

        refreshChallengesAndRewards()
        refreshAchievements()
        persist()
    }

    @discardableResult
    func spendSkillPoint(on axis: GamificationSkillAxis) -> Bool {
        ensureCurrentDay()

        guard skillPoints > 0 else { return false }
        skillPoints -= 1
        addSkillXP(axis, amount: 20, useDailyCap: false)
        persist()
        return true
    }

    func recomputeFocusStreak(from logs: [FocusLogEntry], dailyGoal: Int) {
        ensureCurrentDay()
        updateFocusStreak(from: logs, dailyGoal: dailyGoal, awardConsistency: false)
        refreshAchievements()
        refreshChallengesAndRewards()
        persist()
    }

    // Backward-compatible API used in existing hooks.
    func awardFocus(minutes: Int, logs: [FocusLogEntry], dailyGoal: Int) {
        ensureCurrentDay()

        let boundedMinutes = max(1, minutes)
        grantXP(boundedMinutes)
        totalFocusSessions += 1
        dailyMetrics.focusMinutes += boundedMinutes

        addSkillXP(.focus, amount: boundedMinutes)
        updateFocusStreak(from: logs, dailyGoal: dailyGoal, awardConsistency: true)

        refreshChallengesAndRewards()
        refreshAchievements()
        persist()
    }

    func awardTaskCompletion() {
        ensureCurrentDay()
        grantXP(5)
        totalTasksCompleted += 1
        dailyMetrics.tasksCompleted += 1
        addSkillXP(.planning, amount: 5)
        refreshChallengesAndRewards()
        refreshAchievements()
        persist()
    }

    func awardHabitCompletion() {
        ensureCurrentDay()
        grantXP(10)
        totalHabitsCompleted += 1
        dailyMetrics.habitsCompleted += 1
        addSkillXP(.consistency, amount: 8)
        refreshChallengesAndRewards()
        refreshAchievements()
        persist()
    }

    func awardBonusXP(_ amount: Int, reason: String = "") {
        ensureCurrentDay()
        grantXP(max(0, amount))
        refreshAchievements()
        persist()
    }

    // =====================================================
    // MARK: - Internal Logic
    // =====================================================

    private func updateFocusStreak(from logs: [FocusLogEntry], dailyGoal: Int, awardConsistency: Bool) {
        let goal = max(1, dailyGoal)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let todayCount = logs.filter {
            ($0.phase == .work || $0.phase == .custom) && calendar.isDate($0.startedAt, inSameDayAs: today)
        }.count

        let reachedToday = todayCount >= goal
        if reachedToday, dailyMetrics.reachedDailyGoal == false {
            dailyMetrics.reachedDailyGoal = true
            if awardConsistency {
                addSkillXP(.consistency, amount: 28)
            }
        } else if reachedToday == false {
            dailyMetrics.reachedDailyGoal = false
        }

        var streak = 0
        var cursor = today

        while true {
            let sessionCount = logs.reduce(into: 0) { partial, entry in
                guard entry.phase == .work || entry.phase == .custom else { return }
                guard calendar.isDate(entry.startedAt, inSameDayAs: cursor) else { return }
                partial += 1
            }

            if sessionCount >= goal {
                streak += 1
            } else {
                break
            }

            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previous
        }

        dailyFocusStreak = streak

        if awardConsistency, streak >= 2, reachedToday {
            addSkillXP(.consistency, amount: min(20, streak * 2))
        }
    }

    private func refreshChallengesAndRewards() {
        guard dailyChallenges.isEmpty == false else { return }

        for index in dailyChallenges.indices {
            let progress = challengeProgress(for: dailyChallenges[index].kind)
            let target = max(1, dailyChallenges[index].target)

            dailyChallenges[index].progress = min(progress, target)

            let didComplete = progress >= target
            if didComplete, dailyChallenges[index].completed == false {
                dailyChallenges[index].completed = true
                lastCompletedChallengeID = dailyChallenges[index].id
                challengeCelebrationToken += 1
            }

            if didComplete, dailyChallenges[index].rewarded == false {
                dailyChallenges[index].rewarded = true
                grantXP(dailyChallenges[index].rewardXP)
            }
        }
    }

    private func challengeProgress(for kind: GamificationChallengeKind) -> Int {
        switch kind {
        case .deepFocus:
            return dailyMetrics.focusMinutes
        case .taskSprint:
            return dailyMetrics.tasksCompleted
        case .earlyWin:
            return dailyMetrics.highPriorityBeforeNoon
        case .habitCombo:
            return dailyMetrics.habitsCompleted
        case .consistency:
            return dailyMetrics.reachedDailyGoal ? 1 : 0
        case .cleanInbox:
            return dailyMetrics.tasksCompleted
        case .studySession:
            return dailyMetrics.learningFocusMinutes
        }
    }

    private func refreshAchievements() {
        if totalFocusSessions >= 1 {
            unlock(.firstFocusSession)
        }

        if totalXP >= 100 {
            unlock(.first100XP)
        }

        if dailyFocusStreak >= 7 {
            unlock(.sevenDayFocusStreak)
        }

        if totalTasksCompleted >= 10 {
            unlock(.tenTasksCompleted)
        }

        if totalHabitsCompleted >= 10 {
            unlock(.tenHabitsCompleted)
        }

        if currentLevel >= 10 {
            unlock(.level10Reached)
        }
    }

    private func unlock(_ achievement: GamificationAchievement) {
        if achievementUnlocks[achievement] != nil { return }
        achievementUnlocks[achievement] = Date()
    }

    private func grantXP(_ amount: Int) {
        let bounded = max(0, amount)
        guard bounded > 0 else { return }

        let previousLevel = currentLevel
        totalXP += bounded
        let levelDelta = max(0, currentLevel - previousLevel)
        if levelDelta > 0 {
            skillPoints += levelDelta
        }
    }

    private func addSkillXP(_ axis: GamificationSkillAxis, amount: Int, useDailyCap: Bool = true) {
        let bounded = max(0, amount)
        guard bounded > 0 else { return }

        var grant = bounded
        if useDailyCap {
            let used = dailySkillGain[axis, default: 0]
            let remaining = max(0, 100 - used)
            grant = min(grant, remaining)
            dailySkillGain[axis] = used + grant
        }

        guard grant > 0 else { return }

        var state = skills[axis] ?? GamificationSkillState()
        state.totalXP = min(1999, max(0, state.totalXP + grant))
        skills[axis] = state
    }

    private func ensureCurrentDay() {
        let todayKey = dayKey(from: Date())
        guard dailyMetrics.dayKey != todayKey else { return }

        dailyMetrics = .empty(dayKey: todayKey)
        dailySkillGain = [:]
        let baseline = Self.generateChallenges(for: todayKey)
        dailyChallenges = baseline
        requestChallengePersonalizationIfPossible(dayKey: todayKey, baseline: baseline)
    }

    private func requestChallengePersonalizationIfPossible(dayKey: String, baseline: [GamificationDailyChallenge]) {
        challengePersonalizationTask?.cancel()
        challengePersonalizationTask = nil

        guard let provider = personalizedChallengeProvider else { return }
        guard baseline.isEmpty == false else { return }

        challengePersonalizationTask = Task { [weak self] in
            guard let self else { return }

            let personalized = await provider(dayKey, baseline)
            guard Task.isCancelled == false else { return }
            guard let personalized else { return }
            guard self.dailyMetrics.dayKey == dayKey else { return }
            guard self.hasNoDailyProgressYet else { return }

            let normalized = self.normalizedPersonalizedChallenges(
                personalized,
                dayKey: dayKey,
                fallback: baseline
            )

            guard normalized.isEmpty == false else { return }

            self.dailyChallenges = normalized
            self.refreshChallengesAndRewards()
            self.persist()
        }
    }

    private var hasNoDailyProgressYet: Bool {
        let metricsIdle =
            dailyMetrics.focusMinutes == 0 &&
            dailyMetrics.tasksCompleted == 0 &&
            dailyMetrics.habitsCompleted == 0 &&
            dailyMetrics.highPriorityBeforeNoon == 0 &&
            dailyMetrics.learningFocusMinutes == 0 &&
            dailyMetrics.reachedDailyGoal == false

        let challengesIdle = dailyChallenges.allSatisfy {
            $0.progress == 0 && $0.completed == false && $0.rewarded == false
        }

        return metricsIdle && challengesIdle
    }

    private func normalizedPersonalizedChallenges(
        _ personalized: [GamificationDailyChallenge],
        dayKey: String,
        fallback: [GamificationDailyChallenge]
    ) -> [GamificationDailyChallenge] {
        guard personalized.isEmpty == false else { return fallback }

        var seenKinds = Set<GamificationChallengeKind>()
        var byKind: [GamificationChallengeKind: GamificationDailyChallenge] = [:]

        for challenge in personalized {
            guard seenKinds.insert(challenge.kind).inserted else { continue }
            byKind[challenge.kind] = challenge
        }

        return fallback.map { base in
            let candidate = byKind[base.kind] ?? base

            return GamificationDailyChallenge(
                id: "\(dayKey)-\(base.kind.rawValue)",
                kind: base.kind,
                title: candidate.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? base.title : candidate.title,
                description: candidate.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? base.description : candidate.description,
                rewardXP: normalizedRewardXP(candidate.rewardXP, fallback: base.rewardXP),
                progress: base.progress,
                target: normalizedTarget(for: base.kind, proposed: candidate.target, fallback: base.target),
                completed: base.completed,
                rewarded: base.rewarded
            )
        }
    }

    private func normalizedRewardXP(_ value: Int, fallback: Int) -> Int {
        let base = value > 0 ? value : fallback
        return max(10, min(50, base))
    }

    private func normalizedTarget(for kind: GamificationChallengeKind, proposed: Int, fallback: Int) -> Int {
        switch kind {
        case .earlyWin, .consistency:
            return 1
        case .taskSprint:
            return max(1, min(8, proposed > 0 ? proposed : fallback))
        case .habitCombo:
            return max(1, min(5, proposed > 0 ? proposed : fallback))
        case .cleanInbox:
            return max(1, min(10, proposed > 0 ? proposed : fallback))
        case .deepFocus:
            return max(15, min(120, proposed > 0 ? proposed : fallback))
        case .studySession:
            return max(15, min(180, proposed > 0 ? proposed : fallback))
        }
    }

    private func dayKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func isLearningSource(_ source: String) -> Bool {
        let lower = source.lowercased()
        return lower.contains("study") || lower.contains("learning")
    }

    private func normalizedTokens(_ values: [String]) -> Set<String> {
        let joined = values
            .map { $0.lowercased() }
            .joined(separator: "|")
            .replacingOccurrences(of: ",", with: "|")
            .replacingOccurrences(of: ";", with: "|")

        let pieces = joined
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        return Set(pieces)
    }

    private static func generateChallenges(for dayKey: String) -> [GamificationDailyChallenge] {
        let templates: [GamificationChallengeTemplate] = [
            .init(kind: .deepFocus, title: "Deep Focus", description: "Complete 25 minutes of focus.", target: 25, rewardXP: 25),
            .init(kind: .taskSprint, title: "Task Sprint", description: "Complete 3 tasks today.", target: 3, rewardXP: 25),
            .init(kind: .earlyWin, title: "Early Win", description: "Finish 1 high-priority task before 12:00.", target: 1, rewardXP: 25),
            .init(kind: .habitCombo, title: "Habit Combo", description: "Complete 2 habits today.", target: 2, rewardXP: 25),
            .init(kind: .consistency, title: "Consistency", description: "Reach your daily focus goal.", target: 1, rewardXP: 25),
            .init(kind: .cleanInbox, title: "Clean Inbox", description: "Mark 5 tasks as done.", target: 5, rewardXP: 25),
            .init(kind: .studySession, title: "Study Session", description: "Complete 30 minutes of study/learning focus.", target: 30, rewardXP: 25)
        ]

        let seed = dayKey
            .unicodeScalars
            .map { Int($0.value) }
            .reduce(0) { ($0 &* 31) &+ $1 }

        let ranked = templates.enumerated().sorted { lhs, rhs in
            let leftScore = ((seed &* (lhs.offset + 3)) &+ (lhs.offset * lhs.offset * 17)) % 10_007
            let rightScore = ((seed &* (rhs.offset + 3)) &+ (rhs.offset * rhs.offset * 17)) % 10_007
            return leftScore > rightScore
        }

        return ranked.prefix(3).map { item in
            let template = item.element
            return GamificationDailyChallenge(
                id: "\(dayKey)-\(template.kind.rawValue)",
                kind: template.kind,
                title: template.title,
                description: template.description,
                rewardXP: template.rewardXP,
                progress: 0,
                target: template.target,
                completed: false,
                rewarded: false
            )
        }
    }

    // =====================================================
    // MARK: - Persistence
    // =====================================================

    private func load() {
        ensureDirectory()

        guard let data = try? Data(contentsOf: fileURL),
              let store = try? decoder.decode(GamificationStore.self, from: data) else {
            return
        }

        totalXP = max(0, store.totalXP)
        dailyFocusStreak = max(0, store.dailyFocusStreak)
        skillPoints = max(0, store.skillPoints)

        totalFocusSessions = max(0, store.totalFocusSessions)
        totalTasksCompleted = max(0, store.totalTasksCompleted)
        totalHabitsCompleted = max(0, store.totalHabitsCompleted)

        for axis in GamificationSkillAxis.allCases {
            let value = max(0, store.skillTotalXP[axis.rawValue] ?? 0)
            skills[axis] = GamificationSkillState(totalXP: value)
        }

        var decodedUnlocks: [GamificationAchievement: Date] = [:]
        for (rawKey, date) in store.achievementUnlocks {
            if let key = GamificationAchievement(rawValue: rawKey) {
                decodedUnlocks[key] = date
            }
        }
        achievementUnlocks = decodedUnlocks

        if let legacy = store.legacyUnlockedAchievements {
            let now = Date()
            for achievement in legacy where achievementUnlocks[achievement] == nil {
                achievementUnlocks[achievement] = now
            }
        }

        dailyMetrics = store.dailyMetrics

        var decodedDailyGain: [GamificationSkillAxis: Int] = [:]
        for (rawKey, value) in store.dailySkillGain {
            guard let axis = GamificationSkillAxis(rawValue: rawKey) else { continue }
            decodedDailyGain[axis] = max(0, value)
        }
        dailySkillGain = decodedDailyGain

        dailyChallenges = store.dailyChallenges
    }

    private func persist() {
        ensureDirectory()

        let store = GamificationStore(
            totalXP: totalXP,
            dailyFocusStreak: dailyFocusStreak,
            skillPoints: skillPoints,
            totalFocusSessions: totalFocusSessions,
            totalTasksCompleted: totalTasksCompleted,
            totalHabitsCompleted: totalHabitsCompleted,
            skillTotalXP: Dictionary(uniqueKeysWithValues: skills.map { ($0.key.rawValue, $0.value.totalXP) }),
            achievementUnlocks: Dictionary(uniqueKeysWithValues: achievementUnlocks.map { ($0.key.rawValue, $0.value) }),
            dailyMetrics: dailyMetrics,
            dailySkillGain: Dictionary(uniqueKeysWithValues: dailySkillGain.map { ($0.key.rawValue, $0.value) }),
            dailyChallenges: dailyChallenges,
            legacyUnlockedAchievements: nil
        )

        guard let data = try? encoder.encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func ensureDirectory() {
        let directory = JSONStorageService.baseDirectory
        if FileManager.default.fileExists(atPath: directory.path) == false {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
