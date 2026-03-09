//
//  StatsView.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import SwiftUI
import Charts

// =====================================================
// MARK: - StatsView
// [TAG: V2_STATS_VIEW]
// =====================================================

struct StatsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case day
        case week
        case month

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: return "Day View"
            case .week: return "Week View"
            case .month: return "Month View"
            }
        }

        var xAxisLabel: String {
            switch self {
            case .day: return "Time of day"
            case .week: return "Day"
            case .month: return "Day of month"
            }
        }
    }

    let logs: [FocusLogEntry]
    let currentStreak: Int
    let accent: Color

    @State private var mode: Mode = .day
    @StateObject private var viewModel: StatsViewModel

    init(logs: [FocusLogEntry], currentStreak: Int, accent: Color) {
        self.logs = logs
        self.currentStreak = currentStreak
        self.accent = accent
        _viewModel = StateObject(wrappedValue: StatsViewModel(logs: logs, currentStreak: currentStreak))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            totalsRow

            Picker("View Mode", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            chartForSelection

            HStack {
                Text(mode.xAxisLabel)
                Spacer(minLength: 0)
                Text("Focus minutes")
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .onAppear {
            viewModel.refresh(logs: logs, currentStreak: currentStreak)
        }
        .onChange(of: logs.count) { _, _ in
            viewModel.refresh(logs: logs, currentStreak: currentStreak)
        }
        .onChange(of: currentStreak) { _, newValue in
            viewModel.refresh(logs: logs, currentStreak: newValue)
        }
    }

    private var totalsRow: some View {
        HStack(spacing: 10) {
            StatChip(label: "Total", value: "\(viewModel.totals.totalMinutes)m", accent: accent)
            StatChip(label: "Avg/Day", value: "\(viewModel.totals.averagePerDay)m", accent: accent)
            StatChip(label: "Best", value: "\(viewModel.totals.bestDayLabel) · \(viewModel.totals.bestDayMinutes)m", accent: accent)
            StatChip(label: "Streak", value: "\(viewModel.totals.currentStreak)d", accent: accent)
        }
    }

    @ViewBuilder
    private var chartForSelection: some View {
        switch mode {
        case .day:
            Chart(viewModel.dayPoints) { point in
                BarMark(
                    x: .value("Time of Day", point.hour),
                    y: .value("Focus minutes", point.minutes)
                )
                .foregroundStyle(accent.gradient)
                .cornerRadius(2)
            }
            .chartXScale(domain: 0...23)
            .chartXAxis {
                AxisMarks(values: Array(stride(from: 0, through: 23, by: 3))) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(String(format: "%02d", hour))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)

        case .week:
            Chart(viewModel.weekPoints) { point in
                BarMark(
                    x: .value("Day", point.label),
                    y: .value("Focus minutes", point.minutes)
                )
                .foregroundStyle(accent.opacity(0.86).gradient)
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)

        case .month:
            Chart(viewModel.monthPoints) { point in
                BarMark(
                    x: .value("Day of month", point.dayNumber),
                    y: .value("Focus minutes", point.minutes)
                )
                .foregroundStyle(accent.opacity(0.74).gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: monthAxisTicks()) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let day = value.as(Int.self) {
                            Text("\(day)")
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)
        }
    }

    private func monthAxisTicks() -> [Int] {
        let count = viewModel.monthPoints.count
        guard count > 0 else { return [] }

        if count <= 10 {
            return Array(1...count)
        }

        let step = max(1, count / 8)
        var ticks = stride(from: 1, through: count, by: step).map { $0 }
        if ticks.last != count {
            ticks.append(count)
        }
        return ticks
    }
}
