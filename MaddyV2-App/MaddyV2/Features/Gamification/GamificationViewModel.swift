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
        let progress0to1: Double
        let normalized0to1: Double
        let color: Color

        var id: String { axis.rawValue }
    }

    struct ChallengeRow: Identifiable {
        let id: String
        let title: String
        let description: String
        let progress: Int
        let target: Int
        let rewardXP: Int
        let completed: Bool
    }

    struct AchievementRow: Identifiable {
        let achievement: GamificationAchievement
        let unlockedAt: Date?

        var id: String { achievement.rawValue }
        var title: String { achievement.title }
        var description: String { achievement.description }
        var unlocked: Bool { unlockedAt != nil }
    }

    @Published private(set) var levelTitle: String = "Level 1"
    @Published private(set) var xpSubtitle: String = "0 / 100 XP"
    @Published private(set) var progress0to1: Double = 0
    @Published private(set) var skillPoints: Int = 0

    @Published private(set) var radarAxes: [RadarHexChart.AxisValue] = []
    @Published private(set) var skillRows: [SkillRow] = []
    @Published private(set) var challenges: [ChallengeRow] = []
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

    func spendSkillPoint(on axis: GamificationSkillAxis) {
        guard service.spendSkillPoint(on: axis) else { return }
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
        xpSubtitle = "\(service.xpInLevel) / 100 XP"
        progress0to1 = service.progress0to1
        skillPoints = service.skillPoints

        let rows = GamificationSkillAxis.allCases.enumerated().map { index, axis in
            let state = service.skills[axis] ?? GamificationSkillState()
            let color = tone(for: index)
            return SkillRow(
                axis: axis,
                title: axis.title,
                level: state.skillLevel,
                xpInLevel: state.skillXP,
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

        challenges = service.dailyChallenges.map {
            ChallengeRow(
                id: $0.id,
                title: $0.title,
                description: $0.description,
                progress: $0.progress,
                target: $0.target,
                rewardXP: $0.rewardXP,
                completed: $0.completed
            )
        }

        achievements = GamificationAchievement.allCases.map {
            AchievementRow(achievement: $0, unlockedAt: service.unlockedAt(for: $0))
        }
    }

    private func tone(for index: Int) -> Color {
        let steps: [Double] = [0.98, 0.88, 0.78, 0.68, 0.58, 0.48]
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
