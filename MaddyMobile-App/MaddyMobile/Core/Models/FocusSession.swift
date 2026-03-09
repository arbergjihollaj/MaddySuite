import Foundation

// =====================================================
// MARK: - Focus Models
// [TAG: MOBILE_FOCUS_MODEL]
// =====================================================

enum FocusMode: String, Codable, CaseIterable, Identifiable {
    case pomodoro
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pomodoro: return "Pomodoro"
        case .custom: return "Custom"
        }
    }
}

struct FocusSession: Identifiable, Codable, Equatable {
    var id: UUID
    var startDate: Date
    var endDate: Date
    var durationMinutes: Int
    var mode: FocusMode
}
