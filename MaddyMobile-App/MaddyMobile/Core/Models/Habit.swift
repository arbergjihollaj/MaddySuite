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
