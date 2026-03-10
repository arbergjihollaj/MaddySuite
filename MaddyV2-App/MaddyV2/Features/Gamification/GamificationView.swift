//
//  GamificationView.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI

// =====================================================
// MARK: - Gamification View
// [TAG: V2_GAMIFICATION_VIEW]
// =====================================================

struct GamificationView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: GamificationViewModel
    let accent: Color

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                profileCard
                challengesCard
                seasonCard
                recoveryCard
                achievementsCard
            }
            .padding(.bottom, 12)
        }
        .onAppear {
            viewModel.updateAccent(accent)
        }
    }

    private var headerCard: some View {
        GlassCard(accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.levelTitle)
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Spacer(minLength: 0)

                    Text(viewModel.momentumText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                }

                ProgressView(value: viewModel.progress0to1)
                    .tint(accent)
                    .scaleEffect(x: 1, y: 1.2, anchor: .center)

                HStack {
                    Text(viewModel.xpSubtitle)
                    Spacer(minLength: 0)
                    Text(viewModel.specializationText)
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

                Text(viewModel.specializationSummaryText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .animation(.easeInOut(duration: 0.22), value: viewModel.progress0to1)
        }
    }

    private var profileCard: some View {
        GlassCard(title: "Skill Profile", accent: accent) {
            VStack(spacing: 12) {
                RadarHexChart(axes: viewModel.radarAxes)
                    .frame(height: 300)

                ForEach(viewModel.skillRows) { skill in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(skill.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Spacer(minLength: 0)
                            Text("Lv \(skill.level)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: skill.progress0to1)
                            .tint(skill.color)

                        Text("\(skill.xpInLevel)/\(skill.xpToNext) XP")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                }
            }
        }
    }

    private var challengesCard: some View {
        GlassCard(title: "Challenges", accent: accent) {
            VStack(spacing: 12) {
                challengeSection(title: "Daily", items: viewModel.dailyChallenges)
                challengeSection(title: "Weekly", items: viewModel.weeklyChallenges)
                challengeSection(title: "Seasonal", items: viewModel.seasonalChallenges)
                Text(viewModel.weeklyGoalText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func challengeSection(title: String, items: [GamificationViewModel.ChallengeRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text("No challenges")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { challenge in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(challenge.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Spacer(minLength: 0)
                            Text("+\(challenge.rewardXP) XP")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(accent)
                        }

                        Text(challenge.description)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        ProgressView(value: Double(challenge.progress), total: Double(max(1, challenge.target)))
                            .tint(challenge.completed ? .green : accent)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(challenge.completed ? Color.green.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }

    private var seasonCard: some View {
        GlassCard(title: "Season", accent: accent) {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.seasonTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(viewModel.seasonSubtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recoveryCard: some View {
        GlassCard(title: "Recovery / Reset", accent: accent) {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.recoveryText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Mark Recovery Complete") {
                        appState.gamificationService.completeRecoveryChallenge()
                    }
                    .buttonStyle(.bordered)

                    Button("Activate Reset Day") {
                        appState.gamificationService.activateResetDayIfAvailable()
                    }
                    .buttonStyle(.bordered)
                }

                Text(viewModel.resetDayText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var achievementsCard: some View {
        GlassCard(title: "Achievements", accent: accent) {
            if viewModel.achievements.isEmpty {
                Text("No achievements unlocked yet")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.achievements.prefix(8)) { achievement in
                        HStack(spacing: 10) {
                            Image(systemName: achievement.icon)
                                .foregroundStyle(accent)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(achievement.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                Text(achievement.description)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
                }
            }
        }
    }
}
