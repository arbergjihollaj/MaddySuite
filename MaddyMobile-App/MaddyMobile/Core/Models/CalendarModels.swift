import Foundation

// =====================================================
// MARK: - Calendar Models
// [TAG: MOBILE_CALENDAR_MODELS]
// =====================================================

enum CalendarViewMode: String, Codable, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
}

enum CalendarEntrySource: String, Codable {
    case google
    case ical
    case task

    var title: String {
        switch self {
        case .google: return "Google"
        case .ical: return "iCal"
        case .task: return "Task"
        }
    }
}

struct CalendarEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let source: CalendarEntrySource
    let sourceName: String
    let isCompletedTask: Bool

    init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        source: CalendarEntrySource,
        sourceName: String,
        isCompletedTask: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = max(endDate, startDate)
        self.isAllDay = isAllDay
        self.source = source
        self.sourceName = sourceName
        self.isCompletedTask = isCompletedTask
    }
}

struct CalendarDaySummary: Identifiable {
    let date: Date
    let entries: [CalendarEntry]

    var id: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct CalendarMonthCell: Identifiable {
    let date: Date
    let isInCurrentMonth: Bool
    let entryCount: Int
    let hasTask: Bool

    var id: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

enum GoogleCalendarConnectionState: Equatable {
    case checking
    case unavailable(String)
    case connected(accountCount: Int)

    var title: String {
        switch self {
        case .checking: return "Checking"
        case .unavailable: return "Unavailable"
        case .connected: return "Connected"
        }
    }

    var subtitle: String {
        switch self {
        case .checking:
            return "Detecting Google calendars"
        case .unavailable(let message):
            return message
        case .connected(let accountCount):
            let noun = accountCount == 1 ? "calendar" : "calendars"
            return "Using \(accountCount) Google \(noun)"
        }
    }

    var symbolName: String {
        switch self {
        case .checking: return "clock"
        case .unavailable: return "cloud.slash"
        case .connected: return "calendar.badge.checkmark"
        }
    }
}

struct ICalSubscription: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var urlString: String
    var isEnabled: Bool
    var lastRefreshAt: Date?
    var lastError: String?

    static func make(urlString: String, name: String? = nil) -> ICalSubscription {
        let cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName: String

        if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            displayName = name
        } else if let host = URL(string: cleaned)?.host, host.isEmpty == false {
            displayName = host
        } else {
            displayName = "Subscribed Calendar"
        }

        return ICalSubscription(
            id: UUID(),
            name: displayName,
            urlString: cleaned,
            isEnabled: true,
            lastRefreshAt: nil,
            lastError: nil
        )
    }
}
