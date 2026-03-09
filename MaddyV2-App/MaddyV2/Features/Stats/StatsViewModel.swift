//
//  StatsViewModel.swift
//  MaddyV2
//
//  Created by Arber on 03.03.26.
//

import Foundation
import Combine

// =====================================================
// MARK: - Stats ViewModel
// [TAG: V2_STATS_VM]
// =====================================================

@MainActor
final class StatsViewModel: ObservableObject {
    struct DayPoint: Identifiable {
        let id: Int
        let hour: Int
        let minutes: Int
    }

    struct AggregatePoint: Identifiable {
        let id = UUID()
        let label: String
        let dayNumber: Int
        let minutes: Int
    }

    struct Totals {
        let totalMinutes: Int
        let averagePerDay: Int
        let bestDayLabel: String
        let bestDayMinutes: Int
        let currentStreak: Int

        static let empty = Totals(
            totalMinutes: 0,
            averagePerDay: 0,
            bestDayLabel: "-",
            bestDayMinutes: 0,
            currentStreak: 0
        )
    }

    @Published private(set) var dayPoints: [DayPoint] = []
    @Published private(set) var weekPoints: [AggregatePoint] = []
    @Published private(set) var monthPoints: [AggregatePoint] = []
    @Published private(set) var totals: Totals = .empty

    private let calendar: Calendar

    init(logs: [FocusLogEntry], currentStreak: Int) {
        var cal = Calendar.current
        cal.firstWeekday = 2
        self.calendar = cal

        refresh(logs: logs, currentStreak: currentStreak)
    }

    func refresh(logs: [FocusLogEntry], currentStreak: Int) {
        let focusLogs = logs.filter { $0.phase == .work || $0.phase == .custom }

        dayPoints = makeDayPoints(from: focusLogs)
        weekPoints = makeWeekPoints(from: focusLogs)
        monthPoints = makeMonthPoints(from: focusLogs)
        totals = makeTotals(from: focusLogs, currentStreak: currentStreak)
    }

    // =====================================================
    // MARK: - Day / Week / Month
    // [TAG: V2_STATS_AGGREGATION]
    // =====================================================

    private func makeDayPoints(from logs: [FocusLogEntry]) -> [DayPoint] {
        let today = Date()
        let filtered = logs.filter { calendar.isDate($0.startedAt, inSameDayAs: today) }

        var buckets = Array(repeating: 0, count: 24)
        for entry in filtered {
            let hour = calendar.component(.hour, from: entry.startedAt)
            guard (0..<24).contains(hour) else { continue }
            buckets[hour] += max(1, entry.durationSeconds / 60)
        }

        return (0..<24).map { hour in
            DayPoint(id: hour, hour: hour, minutes: buckets[hour])
        }
    }

    private func makeWeekPoints(from logs: [FocusLogEntry]) -> [AggregatePoint] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return []
        }

        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        return (0..<7).compactMap { index in
            guard let dayDate = calendar.date(byAdding: .day, value: index, to: weekInterval.start) else {
                return nil
            }

            let minutes = minutes(on: dayDate, from: logs)
            return AggregatePoint(label: labels[index], dayNumber: index + 1, minutes: minutes)
        }
    }

    private func makeMonthPoints(from logs: [FocusLogEntry]) -> [AggregatePoint] {
        let now = Date()
        guard let range = calendar.range(of: .day, in: .month, for: now) else {
            return []
        }

        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)

        return range.compactMap { day in
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            guard let date = calendar.date(from: components) else {
                return nil
            }

            let minutes = minutes(on: date, from: logs)
            return AggregatePoint(label: "\(day)", dayNumber: day, minutes: minutes)
        }
    }

    // =====================================================
    // MARK: - Totals
    // [TAG: V2_STATS_TOTALS]
    // =====================================================

    private func makeTotals(from logs: [FocusLogEntry], currentStreak: Int) -> Totals {
        guard logs.isEmpty == false else {
            return Totals(
                totalMinutes: 0,
                averagePerDay: 0,
                bestDayLabel: "-",
                bestDayMinutes: 0,
                currentStreak: currentStreak
            )
        }

        let totalMinutes = logs.reduce(0) { $0 + max(1, $1.durationSeconds / 60) }

        let firstDay = calendar.startOfDay(for: logs.map(\.startedAt).min() ?? Date())
        let today = calendar.startOfDay(for: Date())
        let spanDays = (calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0) + 1
        let daySpan = max(1, spanDays)

        var perDay: [String: Int] = [:]
        for entry in logs {
            let key = calendar.startOfDay(for: entry.startedAt).yyyymmdd
            perDay[key, default: 0] += max(1, entry.durationSeconds / 60)
        }

        let best = perDay.max { $0.value < $1.value }
        let bestLabel = best.map { key, _ in
            Self.bestLabel(from: key)
        } ?? "-"

        return Totals(
            totalMinutes: totalMinutes,
            averagePerDay: totalMinutes / daySpan,
            bestDayLabel: bestLabel,
            bestDayMinutes: best?.value ?? 0,
            currentStreak: currentStreak
        )
    }

    private func minutes(on day: Date, from logs: [FocusLogEntry]) -> Int {
        logs.reduce(0) { partial, entry in
            guard calendar.isDate(entry.startedAt, inSameDayAs: day) else { return partial }
            return partial + max(1, entry.durationSeconds / 60)
        }
    }

    private static func bestLabel(from yyyyMMdd: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let output = DateFormatter()
        output.locale = Locale(identifier: "en_US_POSIX")
        output.dateFormat = "dd.MM"

        guard let date = formatter.date(from: yyyyMMdd) else {
            return yyyyMMdd
        }

        return output.string(from: date)
    }
}
