import Foundation
import Combine
import EventKit
#if canImport(UIKit)
import UIKit
#endif

// =====================================================
// MARK: - CalendarStore
// [TAG: MOBILE_CALENDAR_STORE]
// =====================================================

@MainActor
final class CalendarStore: ObservableObject {
    @Published var selectedMode: CalendarViewMode = .week {
        didSet { rebuildVisibleEntries() }
    }

    @Published var anchorDate: Date = Date() {
        didSet { rebuildVisibleEntries() }
    }

    @Published private(set) var visibleEntries: [CalendarEntry] = []
    @Published private(set) var googleConnectionState: GoogleCalendarConnectionState = .checking
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?

    private let settingsStore: SettingsStore
    private let tasksStore: TasksStore
    private let eventStore = EKEventStore()
    private var cancellables: Set<AnyCancellable> = []
    private var periodicRefreshTask: Task<Void, Never>?
    private var isLiveUpdatesEnabled = false
    private var needsRemoteRefresh = true
    private var hasPendingLocalChanges = true

    private var googleEntries: [CalendarEntry] = []
    private var icalEntriesBySubscription: [UUID: [CalendarEntry]] = [:]
    private var mergedEntries: [CalendarEntry] = []
    private var entriesByDayKey: [String: [CalendarEntry]] = [:]
    private var entryCountByDayKey: [String: Int] = [:]
    private var hasTaskByDayKey: Set<String> = []

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        return value
    }

    init(settingsStore: SettingsStore, tasksStore: TasksStore) {
        self.settingsStore = settingsStore
        self.tasksStore = tasksStore
        bind()
    }

    deinit {
        periodicRefreshTask?.cancel()
    }

    var periodTitle: String {
        switch selectedMode {
        case .day:
            return anchorDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        case .week:
            let interval = currentPeriodInterval()
            let start = interval.start.formatted(.dateTime.day().month(.abbreviated))
            let end = interval.end.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated).year())
            return "\(start) – \(end)"
        case .month:
            return anchorDate.formatted(.dateTime.month(.wide).year())
        }
    }

    var shouldShowCompletedTasks: Bool {
        false
    }

    func setMode(_ mode: CalendarViewMode) {
        guard selectedMode != mode else { return }
        selectedMode = mode
    }

    func selectDate(_ date: Date) {
        anchorDate = date
    }

    func goToPreviousPeriod() {
        switch selectedMode {
        case .day:
            anchorDate = calendar.date(byAdding: .day, value: -1, to: anchorDate) ?? anchorDate
        case .week:
            anchorDate = calendar.date(byAdding: .day, value: -7, to: anchorDate) ?? anchorDate
        case .month:
            anchorDate = calendar.date(byAdding: .month, value: -1, to: anchorDate) ?? anchorDate
        }
    }

    func goToNextPeriod() {
        switch selectedMode {
        case .day:
            anchorDate = calendar.date(byAdding: .day, value: 1, to: anchorDate) ?? anchorDate
        case .week:
            anchorDate = calendar.date(byAdding: .day, value: 7, to: anchorDate) ?? anchorDate
        case .month:
            anchorDate = calendar.date(byAdding: .month, value: 1, to: anchorDate) ?? anchorDate
        }
    }

    func daySummariesForVisiblePeriod() -> [CalendarDaySummary] {
        let interval = currentPeriodInterval()
        var summaries: [CalendarDaySummary] = []
        var day = calendar.startOfDay(for: interval.start)
        let endBoundary = interval.end

        while day < endBoundary {
            let key = Self.dayKey(for: day, calendar: calendar)
            if let entries = entriesByDayKey[key], entries.isEmpty == false {
                summaries.append(CalendarDaySummary(date: day, entries: entries))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return summaries
    }

    func monthCells() -> [CalendarMonthCell] {
        let monthStart = startOfMonth(anchorDate)
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) ?? monthStart

        let monthRange = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<32
        let monthLength = monthRange.count
        let totalCells = ((leadingDays + monthLength + 6) / 7) * 7

        return (0..<max(totalCells, 35)).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: gridStart) else { return nil }
            let sameMonth = calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
            let key = Self.dayKey(for: date, calendar: calendar)
            return CalendarMonthCell(
                date: date,
                isInCurrentMonth: sameMonth,
                entryCount: entryCountByDayKey[key] ?? 0,
                hasTask: hasTaskByDayKey.contains(key)
            )
        }
    }

    func entriesForSelectedDay() -> [CalendarEntry] {
        entries(forDay: anchorDate)
    }

    func setLiveUpdatesEnabled(_ enabled: Bool) {
        guard isLiveUpdatesEnabled != enabled else { return }
        isLiveUpdatesEnabled = enabled

        if enabled {
            startPeriodicRefreshLoop()
            if needsRemoteRefresh {
                Task { [weak self] in
                    await self?.refreshAll(forceCalendarPermissionPrompt: false)
                }
            } else if hasPendingLocalChanges {
                rebuildVisibleEntries()
                hasPendingLocalChanges = false
            }
        } else {
            periodicRefreshTask?.cancel()
            periodicRefreshTask = nil
        }
    }

    func refreshIfNeeded(maxAge: TimeInterval = 60, forceCalendarPermissionPrompt: Bool = false) async {
        if forceCalendarPermissionPrompt {
            await refreshAll(forceCalendarPermissionPrompt: true)
            return
        }

        if let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < maxAge, needsRemoteRefresh == false {
            if hasPendingLocalChanges {
                rebuildVisibleEntries()
                hasPendingLocalChanges = false
            }
            return
        }

        await refreshAll(forceCalendarPermissionPrompt: false)
    }

    func refreshAll(forceCalendarPermissionPrompt: Bool) async {
        guard isRefreshing == false else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshAt = Date()
            needsRemoteRefresh = false
            hasPendingLocalChanges = false
        }

        await refreshGoogleEvents(requestAccessIfNeeded: forceCalendarPermissionPrompt)
        await refreshICalEvents()
        rebuildVisibleEntries()
    }

    func requestGoogleConnection() {
        Task { [weak self] in
            await self?.refreshAll(forceCalendarPermissionPrompt: true)
        }
    }

    func openSystemSettings() {
#if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
#endif
    }

    private func bind() {
        tasksStore.$tasks
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.hasPendingLocalChanges = true
                guard self.isLiveUpdatesEnabled else { return }
                self.rebuildVisibleEntries()
            }
            .store(in: &cancellables)

        settingsStore.$showTaskCalendarEntries
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.hasPendingLocalChanges = true
                guard self.isLiveUpdatesEnabled else { return }
                self.rebuildVisibleEntries()
            }
            .store(in: &cancellables)

        settingsStore.$showGoogleCalendarEvents
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.needsRemoteRefresh = true
                    guard self.isLiveUpdatesEnabled else { return }
                    Task { [weak self] in
                        await self?.refreshGoogleEvents(requestAccessIfNeeded: false)
                        self?.rebuildVisibleEntries()
                    }
                } else {
                    self.googleEntries = []
                    self.googleConnectionState = .unavailable("Hidden in Settings")
                    self.hasPendingLocalChanges = true
                    self.rebuildVisibleEntries()
                }
            }
            .store(in: &cancellables)

        settingsStore.$showICalCalendarEvents
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.needsRemoteRefresh = true
                    guard self.isLiveUpdatesEnabled else { return }
                    Task { [weak self] in
                        await self?.refreshICalEvents()
                        self?.rebuildVisibleEntries()
                    }
                } else {
                    self.hasPendingLocalChanges = true
                    self.rebuildVisibleEntries()
                }
            }
            .store(in: &cancellables)

        settingsStore.$iCalSubscriptions
            .map(Self.subscriptionConfigSignature)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.needsRemoteRefresh = true
                self.hasPendingLocalChanges = true
                guard self.isLiveUpdatesEnabled else { return }
                Task { [weak self] in
                    await self?.refreshICalEvents()
                    self?.rebuildVisibleEntries()
                }
            }
            .store(in: &cancellables)
    }

    private func startPeriodicRefreshLoop() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 1_800_000_000_000)
                guard let self else { return }
                guard self.isLiveUpdatesEnabled else { return }
                await self.refreshAll(forceCalendarPermissionPrompt: false)
            }
        }
    }

    private func rebuildVisibleEntries() {
        var result: [CalendarEntry] = []

        if settingsStore.showTaskCalendarEntries {
            result.append(contentsOf: taskEntries())
        }

        if settingsStore.showGoogleCalendarEvents {
            result.append(contentsOf: googleEntries)
        }

        if settingsStore.showICalCalendarEvents {
            let enabled = Set(settingsStore.iCalSubscriptions.filter(\.isEnabled).map(\.id))
            for (id, values) in icalEntriesBySubscription where enabled.contains(id) {
                result.append(contentsOf: values)
            }
        }

        mergedEntries = result.sorted { lhs, rhs in
            if lhs.startDate == rhs.startDate {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.startDate < rhs.startDate
        }

        let caches = Self.buildDayCaches(from: mergedEntries, calendar: calendar)
        entriesByDayKey = caches.entriesByDayKey
        entryCountByDayKey = caches.entryCountByDayKey
        hasTaskByDayKey = caches.hasTaskByDayKey

        let period = currentPeriodInterval()
        visibleEntries = mergedEntries.filter { entry in
            entry.endDate >= period.start && entry.startDate < period.end
        }
    }

    private func taskEntries() -> [CalendarEntry] {
        let activeTasks = tasksStore.tasks
            .filter { $0.status != .done || shouldShowCompletedTasks }
            .filter { $0.dueDate != nil }

        return activeTasks.compactMap { task in
            guard let dueDate = task.dueDate else { return nil }
            let endDate = dueDate.addingTimeInterval(45 * 60)
            return CalendarEntry(
                id: "task-\(task.id.uuidString)",
                title: task.title,
                startDate: dueDate,
                endDate: endDate,
                isAllDay: false,
                source: .task,
                sourceName: "Maddy Task",
                isCompletedTask: task.status == .done
            )
        }
    }

    private func refreshGoogleEvents(requestAccessIfNeeded: Bool) async {
        guard settingsStore.showGoogleCalendarEvents else {
            googleEntries = []
            googleConnectionState = .unavailable("Hidden in Settings")
            return
        }

        let access = await requestEventStoreAccess(shouldPrompt: requestAccessIfNeeded)
        switch access {
        case .granted:
            break
        case .notDetermined:
            googleEntries = []
            googleConnectionState = .unavailable("Allow Calendar access to use Google events")
            return
        case .denied(let message):
            googleEntries = []
            googleConnectionState = .unavailable(message)
            return
        }

        let googleCalendars = eventStore.calendars(for: .event).filter(Self.isGoogleCalendar)
        guard googleCalendars.isEmpty == false else {
            googleEntries = []
            googleConnectionState = .unavailable("No Google calendars found on this iPhone")
            return
        }

        let rangeStart = calendar.date(byAdding: .month, value: -1, to: anchorDate) ?? anchorDate
        let rangeEnd = calendar.date(byAdding: .month, value: 6, to: anchorDate) ?? anchorDate.addingTimeInterval(60 * 60 * 24 * 180)
        let predicate = eventStore.predicateForEvents(withStart: rangeStart, end: rangeEnd, calendars: googleCalendars)
        let events = eventStore.events(matching: predicate)

        googleEntries = events.map { event in
            CalendarEntry(
                id: "google-\(event.calendarItemIdentifier)",
                title: event.title?.isEmpty == false ? event.title! : "Untitled Event",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                source: .google,
                sourceName: event.calendar.title
            )
        }
        googleConnectionState = .connected(accountCount: googleCalendars.count)
    }

    private func refreshICalEvents() async {
        let subscriptions = settingsStore.iCalSubscriptions.filter(\.isEnabled)
        guard subscriptions.isEmpty == false else {
            icalEntriesBySubscription = [:]
            return
        }

        await withTaskGroup(of: ICalRefreshResult.self) { group in
            for subscription in subscriptions {
                group.addTask {
                    await Self.fetchSubscription(subscription)
                }
            }

            var next: [UUID: [CalendarEntry]] = icalEntriesBySubscription

            for await result in group {
                switch result {
                case .success(let id, let entries):
                    next[id] = entries
                case .failure(let id, let message):
                    _ = id
                    _ = message
                }
            }

            icalEntriesBySubscription = next
        }
    }

    private func currentPeriodInterval() -> DateInterval {
        switch selectedMode {
        case .day:
            let start = calendar.startOfDay(for: anchorDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
            return DateInterval(start: start, end: end)
        case .week:
            let start = startOfWeek(anchorDate)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
            return DateInterval(start: start, end: end)
        case .month:
            let start = startOfMonth(anchorDate)
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(31 * 86_400)
            return DateInterval(start: start, end: end)
        }
    }

    private func startOfWeek(_ date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func startOfMonth(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func entries(forDay date: Date) -> [CalendarEntry] {
        entriesByDayKey[Self.dayKey(for: date, calendar: calendar)] ?? []
    }

    private static func isGoogleCalendar(_ calendar: EKCalendar) -> Bool {
        let source = calendar.source.title.lowercased()
        let title = calendar.title.lowercased()
        return source.contains("google") || source.contains("gmail") || title.contains("@gmail")
    }

    private enum AccessResult {
        case granted
        case notDetermined
        case denied(String)
    }

    private func requestEventStoreAccess(shouldPrompt: Bool) async -> AccessResult {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .authorized:
            return .granted
        case .fullAccess:
            return .granted
        case .notDetermined:
            guard shouldPrompt else { return .notDetermined }
            let granted: Bool

            if #available(iOS 17.0, *) {
                granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
            } else {
                granted = await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .event) { accepted, _ in
                        continuation.resume(returning: accepted)
                    }
                }
            }

            return granted ? .granted : .denied("Calendar access was not granted")
        case .denied, .restricted, .writeOnly:
            return .denied("Calendar permission denied. Enable it in iOS Settings")
        @unknown default:
            return .denied("Calendar access unavailable")
        }
    }

    private static func subscriptionConfigSignature(_ subscriptions: [ICalSubscription]) -> String {
        subscriptions
            .map { "\($0.id.uuidString)|\($0.name)|\($0.urlString.lowercased())|\($0.isEnabled ? 1 : 0)" }
            .sorted()
            .joined(separator: ";")
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let start = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: start)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func buildDayCaches(from entries: [CalendarEntry], calendar: Calendar)
        -> (entriesByDayKey: [String: [CalendarEntry]], entryCountByDayKey: [String: Int], hasTaskByDayKey: Set<String>) {
        var buckets: [String: [CalendarEntry]] = [:]
        var hasTask: Set<String> = []

        for entry in entries {
            var day = calendar.startOfDay(for: entry.startDate)
            let endDay = calendar.startOfDay(for: entry.endDate)

            while day <= endDay {
                let key = dayKey(for: day, calendar: calendar)
                buckets[key, default: []].append(entry)
                if entry.source == .task {
                    hasTask.insert(key)
                }

                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        var counts: [String: Int] = [:]
        for (key, values) in buckets {
            counts[key] = values.count
            buckets[key] = values.sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.startDate < rhs.startDate
            }
        }

        return (buckets, counts, hasTask)
    }
}

// =====================================================
// MARK: - iCal Refresh
// [TAG: MOBILE_ICAL_REFRESH]
// =====================================================

private enum ICalRefreshResult {
    case success(id: UUID, entries: [CalendarEntry])
    case failure(id: UUID, message: String)
}

private extension CalendarStore {
    static func fetchSubscription(_ subscription: ICalSubscription) async -> ICalRefreshResult {
        guard let url = normalizedFeedURL(from: subscription.urlString) else {
            return .failure(id: subscription.id, message: "Invalid URL")
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 18
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) == false {
                return .failure(id: subscription.id, message: "HTTP \(http.statusCode)")
            }

            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""

            let events = parseICal(text: text, subscription: subscription)
            return .success(id: subscription.id, entries: events)
        } catch {
            return .failure(id: subscription.id, message: error.localizedDescription)
        }
    }

    static func normalizedFeedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if trimmed.lowercased().hasPrefix("webcal://") {
            let https = "https://" + trimmed.dropFirst("webcal://".count)
            return URL(string: https)
        }

        return URL(string: trimmed)
    }

    static func parseICal(text: String, subscription: ICalSubscription) -> [CalendarEntry] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let rawLines = normalized.components(separatedBy: "\n")
        var unfolded: [String] = []

        for line in rawLines {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                if let last = unfolded.indices.last {
                    unfolded[last] += String(line.dropFirst())
                }
            } else {
                unfolded.append(line)
            }
        }

        struct Buffer {
            var uid: String = ""
            var summary: String = ""
            var start: Date?
            var end: Date?
            var allDay = false
        }

        var entries: [CalendarEntry] = []
        var inEvent = false
        var buffer = Buffer()

        for line in unfolded {
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" {
                inEvent = true
                buffer = Buffer()
                continue
            }

            if upper == "END:VEVENT" {
                if let start = buffer.start {
                    let end = buffer.end ?? start.addingTimeInterval(buffer.allDay ? 86_400 : 3_600)
                    let baseID: String

                    if buffer.uid.isEmpty == false {
                        baseID = buffer.uid
                    } else {
                        baseID = "\(buffer.summary)|\(Int(start.timeIntervalSince1970))"
                    }

                    let eventID = "ical-\(subscription.id.uuidString)-\(sanitizeID(baseID))"
                    let title = buffer.summary.isEmpty ? "Untitled Event" : buffer.summary
                    entries.append(
                        CalendarEntry(
                            id: eventID,
                            title: title,
                            startDate: start,
                            endDate: end,
                            isAllDay: buffer.allDay,
                            source: .ical,
                            sourceName: subscription.name
                        )
                    )
                }

                inEvent = false
                continue
            }

            guard inEvent else { continue }
            guard let field = parseField(line) else { continue }

            switch field.key {
            case "UID":
                buffer.uid = field.value
            case "SUMMARY":
                buffer.summary = unescapeICalText(field.value)
            case "DTSTART":
                let parsed = parseICalDate(value: field.value, parameters: field.parameters)
                buffer.start = parsed.date
                buffer.allDay = parsed.isAllDay
            case "DTEND":
                let parsed = parseICalDate(value: field.value, parameters: field.parameters)
                buffer.end = parsed.date
            default:
                continue
            }
        }

        let calendar = Calendar.current
        let minDate = calendar.date(byAdding: .month, value: -1, to: Date()) ?? .distantPast
        let maxDate = calendar.date(byAdding: .month, value: 6, to: Date()) ?? .distantFuture

        return entries
            .filter { $0.endDate >= minDate && $0.startDate <= maxDate }
            .sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.startDate < rhs.startDate
            }
    }

    static func parseField(_ line: String) -> (key: String, parameters: [String: String], value: String)? {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let head = String(parts[0])
        let value = String(parts[1])
        let keyParts = head.split(separator: ";", omittingEmptySubsequences: false)
        guard let rawKey = keyParts.first else { return nil }

        var parameters: [String: String] = [:]
        for parameter in keyParts.dropFirst() {
            let pair = parameter.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if pair.count == 2 {
                parameters[String(pair[0]).uppercased()] = String(pair[1])
            }
        }

        return (String(rawKey).uppercased(), parameters, value)
    }

    static func parseICalDate(value: String, parameters: [String: String]) -> (date: Date?, isAllDay: Bool) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let valueType = parameters["VALUE"]?.uppercased()
        let tzid = parameters["TZID"]

        if valueType == "DATE" || trimmed.count == 8 {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = TimeZone.current
            return (formatter.date(from: trimmed), true)
        }

        let timezone: TimeZone?
        if let tzid, let resolved = TimeZone(identifier: tzid) {
            timezone = resolved
        } else if trimmed.hasSuffix("Z") {
            timezone = TimeZone(secondsFromGMT: 0)
        } else {
            timezone = TimeZone.current
        }

        let formats = [
            "yyyyMMdd'T'HHmmssXXXXX",
            "yyyyMMdd'T'HHmmXXXXX",
            "yyyyMMdd'T'HHmmss'Z'",
            "yyyyMMdd'T'HHmm'Z'",
            "yyyyMMdd'T'HHmmss",
            "yyyyMMdd'T'HHmm"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timezone
            formatter.dateFormat = format
            if let parsed = formatter.date(from: trimmed) {
                return (parsed, false)
            }
        }

        return (nil, false)
    }

    static func unescapeICalText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    static func sanitizeID(_ value: String) -> String {
        value
            .replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
            .prefix(120)
            .description
    }
}
