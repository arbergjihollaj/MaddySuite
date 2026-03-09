//
//  FocusView.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI

// =====================================================
// MARK: - FocusView
// [TAG: V2_FOCUS_VIEW]
// =====================================================

struct FocusView: View {
    @EnvironmentObject var appState: AppState

    private var vm: FocusViewModel { appState.focusViewModel }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                timerCard
                pomodoroConfigCard
                statsCard
                detailedStatsCard
            }
            .padding(.bottom, 10)
        }
    }

    private var timerCard: some View {
        GlassCard(title: "Focus Timer", accent: appState.accentColor) {
            VStack(spacing: 16) {
                Picker("Phase", selection: Binding(
                    get: { vm.phase },
                    set: { vm.setPomodoroPhase($0) }
                )) {
                    ForEach(FocusPhase.allCases) { phase in
                        Text(phase.label).tag(phase)
                    }
                }
                .pickerStyle(.segmented)

                ZStack {
                    CircularTimerRing(progress: vm.progress, accent: appState.accentColor)
                        .frame(width: 230, height: 230)

                    VStack(spacing: 6) {
                        Text(vm.phase.label)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Text(timeString(vm.remainingSeconds))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        Text("of \(timeString(vm.totalSeconds))")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        vm.toggleRunning()
                    } label: {
                        Image(systemName: vm.running ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(appState.accentColor)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        vm.resetCurrent()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 48, height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var pomodoroConfigCard: some View {
        GlassCard(title: "Pomodoro + Custom", accent: appState.accentColor) {
            VStack(spacing: 12) {
                HStack {
                    Stepper("Work: \(vm.pomodoroWorkMinutes)m", value: Binding(
                        get: { vm.pomodoroWorkMinutes },
                        set: {
                            vm.pomodoroWorkMinutes = max(1, $0)
                            if vm.phase == .work { vm.setPomodoroPhase(.work) }
                        }
                    ), in: 1...120)

                    Stepper("Short: \(vm.pomodoroShortBreakMinutes)m", value: Binding(
                        get: { vm.pomodoroShortBreakMinutes },
                        set: {
                            vm.pomodoroShortBreakMinutes = max(1, $0)
                            if vm.phase == .shortBreak { vm.setPomodoroPhase(.shortBreak) }
                        }
                    ), in: 1...30)
                }

                HStack {
                    Stepper("Long: \(vm.pomodoroLongBreakMinutes)m", value: Binding(
                        get: { vm.pomodoroLongBreakMinutes },
                        set: {
                            vm.pomodoroLongBreakMinutes = max(1, $0)
                            if vm.phase == .longBreak { vm.setPomodoroPhase(.longBreak) }
                        }
                    ), in: 5...60)

                    Stepper("Cycle: \(vm.pomodoroCycleLength)", value: Binding(
                        get: { vm.pomodoroCycleLength },
                        set: { vm.pomodoroCycleLength = max(2, $0) }
                    ), in: 2...8)
                }

                Divider()

                HStack {
                    Stepper("Custom: \(vm.customMinutes)m", value: Binding(
                        get: { vm.customMinutes },
                        set: { vm.customMinutes = max(1, $0) }
                    ), in: 1...180)

                    Button("Use Custom Timer") {
                        vm.applyCustomTimer()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var statsCard: some View {
        GlassCard(title: "Daily Goal, Streak, Stats", accent: appState.accentColor) {
            HStack(spacing: 12) {
                StatChip(label: "Today", value: "\(vm.todaySessions)/\(appState.settings.dailyFocusGoal)", accent: appState.accentColor)
                StatChip(label: "Streak", value: "\(vm.streakDays)d", accent: appState.accentColor)
                StatChip(label: "Week", value: "\(vm.weekMinutes)m", accent: appState.accentColor)
                StatChip(label: "Month", value: "\(vm.monthMinutes)m", accent: appState.accentColor)
                StatChip(label: "Level", value: "Lv \(appState.gamificationService.level)", accent: appState.accentColor)
            }

            HStack(spacing: 10) {
                ProgressView(value: appState.gamificationService.progressToNextLevel)
                    .tint(appState.accentColor)
                Text("\(appState.gamificationService.totalXP) XP")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailedStatsCard: some View {
        // =====================================================
        // MARK: - Focus Stats Mode
        // [TAG: V2_FOCUS_STATS_MODE]
        // =====================================================
        GlassCard(title: "Focus Statistics", accent: appState.accentColor) {
            StatsView(
                logs: vm.logs,
                currentStreak: appState.gamificationService.dailyFocusStreak,
                accent: appState.accentColor
            )
        }
    }

    private func timeString(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
