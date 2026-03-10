import Foundation

// =====================================================
// MARK: - Habit Models
// [TAG: MOBILE_HABIT_MODEL]
// =====================================================

enum HabitGoalKind: String, Codable, CaseIterable, Identifiable {
    case timeBased
    case quantityBased

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeBased: return "Time"
        case .quantityBased: return "Quantity"
        }
    }
}

enum HabitScheduleMode: String, Codable, CaseIterable, Identifiable {
    case weekdays
    case interval

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekdays: return "Weekdays"
        case .interval: return "Every X Days"
        }
    }
}

struct Habit: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var symbol: String
    var colorHex: String
    var goalKind: HabitGoalKind
    var targetValue: Int
    var scheduleMode: HabitScheduleMode
    var weekdays: [Int]
    var everyXDays: Int
    var streak: Int
    var lastCompletedDateKey: String?
    var history: [String: Int]

    static func empty() -> Habit {
        Habit(
            id: UUID(),
            title: "",
            symbol: "checkmark.circle.fill",
            colorHex: "#24C483",
            goalKind: .quantityBased,
            targetValue: 1,
            scheduleMode: .weekdays,
            weekdays: [2, 3, 4, 5, 6],
            everyXDays: 1,
            streak: 0,
            lastCompletedDateKey: nil,
            history: [:]
        )
    }
}

enum HabitSchedule {
    static func normalizedWeekdays(_ weekdays: [Int]) -> [Int] {
        let normalized = Set(weekdays.map { value -> Int in
            switch value {
            case 8:
                return 1 // Legacy Sunday encoding.
            case 1...7:
                return value
            default:
                return 1
            }
        })
        if normalized.isEmpty {
            return [2, 3, 4, 5, 6]
        }
        return normalized.sorted()
    }

    static func weekdayLabels(calendar: Calendar = .current) -> [(value: Int, label: String)] {
        let symbols = calendar.veryShortWeekdaySymbols
        return (1...7).map { day in
            (value: day, label: symbols[day - 1])
        }
    }

    static func isScheduled(_ habit: Habit, on date: Date, calendar: Calendar = .current) -> Bool {
        switch habit.scheduleMode {
        case .weekdays:
            let weekday = calendar.component(.weekday, from: date)
            let plannedDays = normalizedWeekdays(habit.weekdays)
            return plannedDays.contains(weekday)
        case .interval:
            let interval = max(1, habit.everyXDays)
            guard interval > 1 else { return true }
            guard
                let key = habit.lastCompletedDateKey,
                let lastDate = dayDate(from: key)
            else {
                return true
            }
            let start = calendar.startOfDay(for: lastDate)
            let target = calendar.startOfDay(for: date)
            let diff = calendar.dateComponents([.day], from: start, to: target).day ?? 0
            return diff >= interval
        }
    }

    static func nextScheduledDate(for habit: Habit, after date: Date, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: date)
        switch habit.scheduleMode {
        case .weekdays:
            for offset in 0..<15 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                if isScheduled(habit, on: candidate, calendar: calendar) {
                    return candidate
                }
            }
            return nil
        case .interval:
            let interval = max(1, habit.everyXDays)
            guard interval > 1 else { return start }
            guard
                let key = habit.lastCompletedDateKey,
                let lastDate = dayDate(from: key),
                let next = calendar.date(byAdding: .day, value: interval, to: calendar.startOfDay(for: lastDate))
            else {
                return start
            }
            return max(start, next)
        }
    }

    private static func dayDate(from key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }
}
