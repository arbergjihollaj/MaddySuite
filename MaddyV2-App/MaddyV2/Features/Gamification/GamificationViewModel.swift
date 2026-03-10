//
//  GamificationViewModel.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI
import Combine

// =====================================================
// MARK: - Gamification ViewModel
// [TAG: V2_GAMIFICATION_VM]
// =====================================================

@MainActor
final class GamificationViewModel: ObservableObject {
    struct SkillRow: Identifiable {
        let axis: GamificationSkillAxis
        let title: String
        let level: Int
        let xpInLevel: Int
        let xpToNext: Int
        let progress0to1: Double
        let normalized0to1: Double
        let color: Color

        var id: String { axis.rawValue }
    }

    struct ChallengeRow: Identifiable {
        let id: UUID
        let title: String
        let description: String
        let progress: Int
        let target: Int
        let rewardXP: Int
        let cadence: GamificationChallengeCadence
        let completed: Bool
    }

    struct AchievementRow: Identifiable {
        let id: UUID
        let title: String
        let description: String
        let icon: String
        let unlockedAt: Date
    }

    @Published private(set) var levelTitle: String = "Level 1"
    @Published private(set) var xpSubtitle: String = "0 / 100 XP"
    @Published private(set) var progress0to1: Double = 0

    @Published private(set) var momentumText: String = "Momentum 50"
    @Published private(set) var specializationText: String = "None"
    @Published private(set) var specializationSummaryText: String = "No specialization selected"
    @Published private(set) var weeklyGoalText: String = "Weekly Goal 0/5"
    @Published private(set) var seasonTitle: String = "Season"
    @Published private(set) var seasonSubtitle: String = "Season XP 0"
    @Published private(set) var resetDayText: String = "Reset Day inactive"
    @Published private(set) var recoveryText: String = "No active recovery challenge"

    @Published private(set) var radarAxes: [RadarHexChart.AxisValue] = []
    @Published private(set) var skillRows: [SkillRow] = []
    @Published private(set) var dailyChallenges: [ChallengeRow] = []
    @Published private(set) var weeklyChallenges: [ChallengeRow] = []
    @Published private(set) var seasonalChallenges: [ChallengeRow] = []
    @Published private(set) var achievements: [AchievementRow] = []

    @Published private(set) var celebrationToken: Int = 0

    private let service: GamificationService
    private var accent: Color
    private var cancellables = Set<AnyCancellable>()

    init(service: GamificationService, accent: Color) {
        self.service = service
        self.accent = accent

        bind()
        refresh()
    }

    func updateAccent(_ color: Color) {
        accent = color
        refresh()
    }

    private func bind() {
        service.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        service.$challengeCelebrationToken
            .receive(on: DispatchQueue.main)
            .sink { [weak self] token in
                self?.celebrationToken = token
            }
            .store(in: &cancellables)
    }

    private func refresh() {
        levelTitle = "Level \(service.currentLevel)"
        xpSubtitle = "\(service.xpInLevel) / \(service.xpToNextLevel) XP"
        progress0to1 = service.progress0to1

        momentumText = "Momentum \(service.momentum)"
        specializationText = service.specialization.selection.title
        specializationSummaryText = service.specialization.selection.summary
        weeklyGoalText = "Weekly Goal \(service.weeklyGoal.completedDailyCompletions)/\(service.weeklyGoal.requiredDailyCompletions)"
        seasonTitle = service.season.title
        seasonSubtitle = "Season XP \(service.season.seasonalXP) • Perfect Days \(service.season.stats.perfectDays)"
        resetDayText = service.resetDayChallenge.isActive
            ? "Reset challenge: Focus \(service.resetDayChallenge.focusProgress)/\(service.resetDayChallenge.focusTarget), Tasks \(service.resetDayChallenge.taskProgress)/\(service.resetDayChallenge.taskTarget), Habits \(service.resetDayChallenge.habitProgress)/\(service.resetDayChallenge.habitTarget)"
            : "Reset Day inactive"
        recoveryText = service.recoveryChallenge.map { "\($0.title): \($0.detail)" } ?? "No active recovery challenge"

        let rows = GamificationSkillAxis.allCases.enumerated().map { index, axis in
            let state = service.skills[axis] ?? GamificationSkillState()
            let color = tone(for: index)
            return SkillRow(
                axis: axis,
                title: axis.title,
                level: state.skillLevel,
                xpInLevel: state.skillXP,
                xpToNext: state.xpToNextLevel,
                progress0to1: state.skillProgress0to1,
                normalized0to1: state.normalized0to1,
                color: color
            )
        }

        skillRows = rows

        radarAxes = rows.map {
            RadarHexChart.AxisValue(
                id: $0.axis.rawValue,
                label: $0.title,
                value: $0.normalized0to1,
                color: $0.color
            )
        }

        dailyChallenges = service.dailyChallenges.map {
            ChallengeRow(
                id: $0.id,
                title: $0.title,
                description: $0.detail,
                progress: $0.progress,
                target: $0.target,
                rewardXP: $0.rewardXP,
                cadence: $0.cadence,
                completed: $0.completed
            )
        }

        weeklyChallenges = service.weeklyChallenges.map {
            ChallengeRow(
                id: $0.id,
                title: $0.title,
                description: $0.detail,
                progress: $0.progress,
                target: $0.target,
                rewardXP: $0.rewardXP,
                cadence: $0.cadence,
                completed: $0.completed
            )
        }

        seasonalChallenges = service.seasonalChallenges.map {
            ChallengeRow(
                id: $0.id,
                title: $0.title,
                description: $0.detail,
                progress: $0.progress,
                target: $0.target,
                rewardXP: $0.rewardXP,
                cadence: $0.cadence,
                completed: $0.completed
            )
        }

        achievements = service.achievements.map {
            AchievementRow(
                id: $0.id,
                title: $0.title,
                description: $0.detail,
                icon: $0.icon,
                unlockedAt: $0.unlockedAt
            )
        }
    }

    private func tone(for index: Int) -> Color {
        let steps: [Double] = [0.98, 0.88, 0.78, 0.68]
        let opacity = steps[safe: index] ?? 0.75
        return accent.opacity(opacity)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
