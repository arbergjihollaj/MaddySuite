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
    @ObservedObject var viewModel: GamificationViewModel
    let accent: Color

    @State private var confirmAxis: GamificationSkillAxis?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                profileCard
                challengesCard
                achievementsCard
                upgradesCard
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

                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("\(viewModel.skillPoints) SP")
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                }

                ProgressView(value: viewModel.progress0to1)
                    .tint(accent)
                    .scaleEffect(x: 1, y: 1.2, anchor: .center)

                Text(viewModel.xpSubtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .animation(.easeInOut(duration: 0.22), value: viewModel.progress0to1)
        }
    }

    private var profileCard: some View {
        GlassCard(title: "Your Strength Profile", accent: accent) {
            VStack(spacing: 12) {
                RadarHexChart(axes: viewModel.radarAxes)
                    .frame(height: 340)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(viewModel.skillRows) { skill in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(skill.color)
                                .frame(width: 7, height: 7)
                            Text(skill.title)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var challengesCard: some View {
        GlassCard(title: "Daily Challenges", accent: accent) {
            ZStack {
                ChallengeBurstView(trigger: viewModel.celebrationToken, tint: accent)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(viewModel.challenges) { challenge in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 6) {
                                Text(challenge.title)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                Image(systemName: challenge.completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(challenge.completed ? .green : .white.opacity(0.3))
                                    .font(.system(size: 12, weight: .semibold))
                                    .scaleEffect(challenge.completed ? 1.08 : 1.0)
                                    .animation(.easeInOut(duration: 0.2), value: challenge.completed)
                            }

                            Text(challenge.description)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxHeight: .infinity, alignment: .top)

                            ProgressView(value: Double(challenge.progress), total: Double(max(1, challenge.target)))
                                .tint(challenge.completed ? .green : accent)

                            HStack {
                                Text("\(challenge.progress)/\(challenge.target)")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Text("+\(challenge.rewardXP) XP")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(accent)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(challenge.completed ? Color.green.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private var achievementsCard: some View {
        GlassCard(title: "Achievements", accent: accent) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.achievements) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: item.unlocked ? "rosette" : "seal")
                                    .foregroundStyle(item.unlocked ? accent : .white.opacity(0.4))
                                Text(item.title)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }

                            Text(item.description)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Text(item.unlocked ? "Unlocked" : "Locked")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(item.unlocked ? .green : .white.opacity(0.45))
                        }
                        .padding(12)
                        .frame(width: 185, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(item.unlocked ? 0.08 : 0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(item.unlocked ? accent.opacity(0.35) : Color.white.opacity(0.07), lineWidth: 1)
                        )
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var upgradesCard: some View {
        GlassCard(title: "Skill Upgrades", accent: accent) {
            VStack(spacing: 10) {
                ForEach(viewModel.skillRows) { skill in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.title)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                Text("Level \(skill.level)")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Button {
                                confirmAxis = skill.axis
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(viewModel.skillPoints > 0 ? skill.color : .gray)
                            .disabled(viewModel.skillPoints == 0)
                            .popover(
                                isPresented: Binding(
                                    get: { confirmAxis == skill.axis },
                                    set: { showing in
                                        if showing == false, confirmAxis == skill.axis {
                                            confirmAxis = nil
                                        }
                                    }
                                ),
                                arrowEdge: .top
                            ) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Spend Skill Point")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                    Text("Use 1 SP to add +20 XP to \(skill.title).")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)

                                    HStack {
                                        Button("Cancel") {
                                            confirmAxis = nil
                                        }
                                        .buttonStyle(.bordered)

                                        Button("Spend") {
                                            viewModel.spendSkillPoint(on: skill.axis)
                                            confirmAxis = nil
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(skill.color)
                                    }
                                }
                                .padding(14)
                                .frame(width: 250)
                            }
                        }

                        ProgressView(value: skill.progress0to1)
                            .tint(skill.color)

                        Text("\(skill.xpInLevel)/100 XP")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                }
            }
            .animation(.easeInOut(duration: 0.22), value: viewModel.skillRows.map(\.progress0to1))
        }
    }
}

// =====================================================
// MARK: - Challenge Burst
// [TAG: V2_GAMIFICATION_BURST]
// =====================================================

private struct ChallengeBurstView: View {
    let trigger: Int
    let tint: Color

    @State private var animate = false

    private let dots: [Dot] = Dot.makeDots()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(dots) { dot in
                    Circle()
                        .fill(tint.opacity(0.8))
                        .frame(width: dot.size, height: dot.size)
                        .position(
                            x: dot.x * proxy.size.width,
                            y: dot.y * proxy.size.height
                        )
                        .offset(x: animate ? dot.dx : 0, y: animate ? dot.dy : 0)
                        .opacity(animate ? 0 : 0.85)
                        .animation(.easeOut(duration: 0.32).delay(dot.delay), value: animate)
                }
            }
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, _ in
                animate = false
                withAnimation(.easeOut(duration: 0.34)) {
                    animate = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    animate = false
                }
            }
        }
    }

    private struct Dot: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let delay: Double
        let dx: CGFloat
        let dy: CGFloat

        static func makeDots() -> [Dot] {
            var values: [Dot] = []
            for index in 0..<14 {
                values.append(
                    Dot(
                        id: index,
                        x: CGFloat((index * 17) % 100) / 100.0,
                        y: CGFloat((index * 23) % 100) / 100.0,
                        size: CGFloat(3 + (index % 4)),
                        delay: Double(index) * 0.01,
                        dx: CGFloat(((index % 5) - 2)) * 12,
                        dy: CGFloat(-24 - (index % 4) * 10)
                    )
                )
            }
            return values
        }
    }
}
