import SwiftUI

/// File: Features/Focus/FocusView.swift

// =====================================================
// MARK: - FocusView
// [TAG: MOBILE_FOCUS]
// =====================================================

struct FocusView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var focus: FocusStore

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassCard(title: "Mode", accent: settings.accentColor) {
                    Picker("Mode", selection: Binding(
                        get: { focus.selectedMode },
                        set: { focus.setMode($0) }
                    )) {
                        ForEach(FocusMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if focus.selectedMode == .custom {
                        Stepper("Custom Minutes: \(focus.customMinutes)", value: Binding(
                            get: { focus.customMinutes },
                            set: {
                                focus.customMinutes = max(1, $0)
                                focus.reset()
                            }
                        ), in: 1...120)
                    }
                }

                GlassCard(accent: settings.accentColor) {
                    VStack(alignment: .center, spacing: 16) {
                        RingTimerView(progress: focus.progress, text: focus.timeText, accent: settings.accentColor)
                            .frame(maxWidth: .infinity, alignment: .center)

                        HStack(spacing: 14) {
                            Button {
                                focus.startPauseToggle()
                            } label: {
                                Image(systemName: focus.isRunning ? "pause.fill" : "play.fill")
                                    .frame(width: 52, height: 52)
                            }
                            .buttonStyle(FocusControlStyle(accent: settings.accentColor))

                            Button {
                                focus.completeNow()
                                focus.reset()
                            } label: {
                                Image(systemName: "checkmark")
                                    .frame(width: 52, height: 52)
                            }
                            .buttonStyle(FocusControlStyle(accent: settings.accentColor))

                            Button {
                                focus.reset()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .frame(width: 52, height: 52)
                            }
                            .buttonStyle(FocusControlStyle(accent: settings.accentColor))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                GlassCard(title: "Daily Goal", accent: settings.accentColor) {
                    Stepper("\(focus.dailyGoalMinutes) min", value: Binding(
                        get: { focus.dailyGoalMinutes },
                        set: { focus.dailyGoalMinutes = max(10, $0) }
                    ), in: 10...480, step: 10)

                    Text("Today: \(focus.todayFocusMinutes) min")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                GlassCard(title: "Recent Sessions", accent: settings.accentColor) {
                    VStack(spacing: 8) {
                        ForEach(focus.sessions.prefix(6)) { session in
                            HStack {
                                Text(session.mode.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                Spacer()
                                Text("\(session.durationMinutes) min")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }

                        if focus.sessions.isEmpty {
                            Text("No sessions yet")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Focus")
    }
}

private struct FocusControlStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .background(
                Circle()
                    .fill(configuration.isPressed ? accent.opacity(0.4) : Color.white.opacity(0.1))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
