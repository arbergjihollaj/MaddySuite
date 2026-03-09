import Foundation

// =====================================================
// MARK: - GamificationStore
// [TAG: MOBILE_GAMIFICATION_STORE]
// =====================================================

@MainActor
final class GamificationStore: ObservableObject {
    struct State: Codable {
        var totalXP: Int
        var level: Int
        var skills: SkillValues
        var challenges: [DailyChallenge]
        var achievements: [Achievement]
        var xpEntries: [XPEntry]
        var lastModifiedAt: Date?
    }

    struct CloudSnapshot: Codable {
        var totalXP: Int
        var level: Int
        var skills: SkillValues
        var dailyChallenges: [DailyChallenge]
        var achievements: [Achievement]
        var xpEntries: [XPEntry]
        var modifiedAt: Date
    }

    @Published private(set) var totalXP: Int
    @Published private(set) var level: Int
    @Published private(set) var skills: SkillValues
    @Published private(set) var dailyChallenges: [DailyChallenge]
    @Published private(set) var achievements: [Achievement]
    @Published private(set) var xpEntries: [XPEntry]

    var onDataChanged: (() -> Void)?

    private let storage: LocalJSONStorage
    private let fileName = "gamification.json"
    private(set) var lastModifiedAt: Date
    private var isApplyingCloudSnapshot = false

    init(storage: LocalJSONStorage = .shared) {
        self.storage = storage

        let fallback = State(
            totalXP: 0,
            level: 1,
            skills: .zero,
            challenges: [
                DailyChallenge(id: UUID(), title: "Complete 1 focus session", completed: false),
                DailyChallenge(id: UUID(), title: "Finish 1 task", completed: false),
                DailyChallenge(id: UUID(), title: "Mark 1 habit complete", completed: false)
            ],
            achievements: [],
            xpEntries: [],
            lastModifiedAt: .distantPast
        )

        let state = storage.load(State.self, from: fileName, fallback: fallback)
        totalXP = state.totalXP
        level = state.level
        skills = state.skills
        dailyChallenges = state.challenges
        achievements = state.achievements
        xpEntries = state.xpEntries
        lastModifiedAt = state.lastModifiedAt ?? Self.deriveModifiedAt(from: state)

        persist()
    }

    func registerFocus(minutes: Int) {
        let safeMinutes = max(1, minutes)
        addXP(delta: safeMinutes * 2, reason: "Focus session")
        increaseSkill(.focus, by: min(10, safeMinutes / 5 + 1))
        increaseSkill(.consistency, by: 2)
        completeChallenge(containing: "focus")
        unlockIfNeeded(title: "Focus Starter", thresholdXP: 50, icon: "timer")
        touchLocalMutation()
    }

    func registerTaskCompletion() {
        addXP(delta: 18, reason: "Task completed")
        increaseSkill(.discipline, by: 4)
        completeChallenge(containing: "task")
        unlockIfNeeded(title: "Task Finisher", thresholdXP: 120, icon: "checkmark.circle")
        touchLocalMutation()
    }

    func registerHabitCompletion(streak: Int) {
        addXP(delta: 12, reason: "Habit completed")
        increaseSkill(.health, by: 3)
        increaseSkill(.consistency, by: 3)
        if streak >= 7 {
            unlockIfNeeded(title: "7-Day Streak", thresholdXP: 160, icon: "flame.fill")
        }
        completeChallenge(containing: "habit")
        touchLocalMutation()
    }

    func refreshDailyChallengesIfNeeded() {
        let calendar = Calendar.current
        guard let latest = xpEntries.first?.date else { return }
        guard calendar.isDateInToday(latest) == false else { return }

        dailyChallenges = dailyChallenges.map { DailyChallenge(id: $0.id, title: $0.title, completed: false) }
        touchLocalMutation()
    }

    func cloudSnapshot() -> CloudSnapshot {
        CloudSnapshot(
            totalXP: totalXP,
            level: level,
            skills: skills,
            dailyChallenges: dailyChallenges,
            achievements: achievements,
            xpEntries: xpEntries,
            modifiedAt: lastModifiedAt
        )
    }

    func applyCloudSnapshot(_ snapshot: CloudSnapshot) {
        guard snapshot.modifiedAt > lastModifiedAt else { return }

        isApplyingCloudSnapshot = true
        totalXP = snapshot.totalXP
        level = snapshot.level
        skills = snapshot.skills
        dailyChallenges = snapshot.dailyChallenges
        achievements = snapshot.achievements
        xpEntries = snapshot.xpEntries
        lastModifiedAt = snapshot.modifiedAt
        isApplyingCloudSnapshot = false
        persist()
    }

    private func addXP(delta: Int, reason: String) {
        let safe = max(1, delta)
        totalXP += safe
        level = max(1, totalXP / 100 + 1)

        let entry = XPEntry(
            id: UUID(),
            date: Date(),
            delta: safe,
            totalXP: totalXP,
            level: level,
            reason: reason
        )
        xpEntries.insert(entry, at: 0)
    }

    private func increaseSkill(_ category: SkillCategory, by delta: Int) {
        var next = skills
        next[category] = min(100, next[category] + max(1, delta))
        skills = next
    }

    private func completeChallenge(containing token: String) {
        let needle = token.lowercased()
        if let index = dailyChallenges.firstIndex(where: { $0.title.lowercased().contains(needle) }) {
            dailyChallenges[index].completed = true
        }
    }

    private func unlockIfNeeded(title: String, thresholdXP: Int, icon: String) {
        guard totalXP >= thresholdXP else { return }
        guard achievements.contains(where: { $0.title == title }) == false else { return }

        achievements.insert(
            Achievement(id: UUID(), title: title, detail: "Reached \(thresholdXP) XP", icon: icon, unlockedAt: Date()),
            at: 0
        )
    }

    private func touchLocalMutation() {
        guard isApplyingCloudSnapshot == false else { return }
        lastModifiedAt = Date()
        persist()
        onDataChanged?()
    }

    private func persist() {
        let state = State(
            totalXP: totalXP,
            level: level,
            skills: skills,
            challenges: dailyChallenges,
            achievements: achievements,
            xpEntries: xpEntries,
            lastModifiedAt: lastModifiedAt
        )
        storage.save(state, to: fileName)
    }

    private static func deriveModifiedAt(from state: State) -> Date {
        let latestXP = state.xpEntries.map(\.date).max() ?? .distantPast
        let latestAchievement = state.achievements.map(\.unlockedAt).max() ?? .distantPast
        return max(latestXP, latestAchievement)
    }
}
