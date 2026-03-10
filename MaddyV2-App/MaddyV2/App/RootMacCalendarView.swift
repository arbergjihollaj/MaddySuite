//
//  RootMacCalendarView.swift
//  MaddyV2
//
//  Extracted from RootView.swift to isolate calendar feature state and parsing.
//

import SwiftUI
import Combine
import EventKit

// MARK: - macOS Calendar
// [TAG: V2_MAC_CALENDAR]
// =====================================================

struct MacCalendarView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = MacCalendarViewModel()
    @State private var subscriptionConfigSignature = ""

    private let weekdaySymbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let refreshTimer = Timer.publish(every: 1_800, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerControls

                Text(viewModel.periodTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                googleStatusRow

                if viewModel.selectedMode == .month {
                    monthGrid
                    selectedDayAgenda
                } else {
                    agendaList
                }
            }
        }
        .padding(.horizontal, 2)
        .task {
            subscriptionConfigSignature = MacCalendarViewModel.subscriptionConfigSignature(appState.settings.iCalSubscriptions)
            await refreshCalendarIfNeeded(promptAccess: false)
        }
        .onReceive(refreshTimer) { _ in
            Task { await refreshCalendarIfNeeded(promptAccess: false) }
        }
        .onChange(of: appState.tasksViewModel.tasks) { _, _ in
            viewModel.updateTaskEntries(appState.tasksViewModel.tasks)
            viewModel.rebuildVisibleEntries(settings: appState.settings)
        }
        .onChange(of: appState.settings.showGoogleCalendarEvents) { _, _ in
            viewModel.rebuildVisibleEntries(settings: appState.settings)
        }
        .onChange(of: appState.settings.showICalCalendarEvents) { _, _ in
            viewModel.rebuildVisibleEntries(settings: appState.settings)
        }
        .onChange(of: appState.settings.showTaskCalendarEntries) { _, _ in
            viewModel.rebuildVisibleEntries(settings: appState.settings)
        }
        .onChange(of: appState.settings.iCalSubscriptions) { _, newValue in
            let nextSignature = MacCalendarViewModel.subscriptionConfigSignature(newValue)
            guard nextSignature != subscriptionConfigSignature else { return }
            subscriptionConfigSignature = nextSignature
            Task { await refreshCalendar(promptAccess: false) }
        }
    }

    @ViewBuilder
    private var googleStatusRow: some View {
        switch viewModel.googleConnectionState {
        case .connected(let accountCount):
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(appState.accentColor)
                Text("Google calendars connected (\(accountCount))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Refresh") {
                    Task { await refreshCalendar(promptAccess: false) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .unavailable(let reason):
            if appState.settings.showGoogleCalendarEvents {
                HStack(spacing: 8) {
                    Image(systemName: "cloud.slash")
                        .foregroundStyle(.orange)
                    Text(reason)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Connect") {
                        Task { await refreshCalendar(promptAccess: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(appState.accentColor)
                }
            }
        case .checking:
            EmptyView()
        }
    }

    private func refreshCalendar(promptAccess: Bool) async {
        viewModel.updateTaskEntries(appState.tasksViewModel.tasks)
        await viewModel.refreshAll(
            settings: appState.settings,
            promptCalendarAccess: promptAccess
        )
    }

    private func refreshCalendarIfNeeded(promptAccess: Bool) async {
        viewModel.updateTaskEntries(appState.tasksViewModel.tasks)
        await viewModel.refreshIfNeeded(
            settings: appState.settings,
            maxAge: 120,
            promptCalendarAccess: promptAccess
        )
    }

    private var headerControls: some View {
        HStack(spacing: 10) {
            navButton(systemName: "chevron.left") {
                viewModel.goToPreviousPeriod()
            }

            Spacer(minLength: 8)

            Picker("View", selection: Binding(
                get: { viewModel.selectedMode },
                set: { viewModel.setMode($0, settings: appState.settings) }
            )) {
                ForEach(MacCalendarViewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            Spacer(minLength: 8)

            navButton(systemName: "chevron.right") {
                viewModel.goToNextPeriod()
            }
        }
    }

    private func navButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var monthGrid: some View {
        GlassCard(title: "Calendar", accent: appState.accentColor) {
            VStack(spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(viewModel.monthCells()) { cell in
                        Button {
                            viewModel.selectDate(cell.date, settings: appState.settings)
                        } label: {
                            monthCellContent(cell)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func monthCellContent(_ cell: MacCalendarMonthCell) -> some View {
        let isSelected = Calendar.current.isDate(cell.date, inSameDayAs: viewModel.anchorDate)

        return VStack(spacing: 5) {
            Text(cell.date.formatted(.dateTime.day()))
                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundStyle(cell.isInCurrentMonth ? .white : .secondary)

            if cell.entryCount > 0 {
                HStack(spacing: 3) {
                    Circle()
                        .fill(cell.hasTask ? appState.accentColor : Color.blue.opacity(0.85))
                        .frame(width: 5, height: 5)
                    Text("\(min(cell.entryCount, 9))")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                Color.clear.frame(height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? appState.accentColor.opacity(0.22) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? appState.accentColor.opacity(0.6) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var selectedDayAgenda: some View {
        GlassCard(title: "Selected Day", accent: appState.accentColor) {
            let entries = viewModel.entriesForSelectedDay()

            if entries.isEmpty {
                Text("No events or tasks")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(entries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
    }

    private var agendaList: some View {
        let groups = viewModel.daySummariesForVisiblePeriod()

        return Group {
            if groups.isEmpty {
                GlassCard(accent: appState.accentColor) {
                    Text("No events or tasks in this period")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(groups) { summary in
                        GlassCard(accent: appState.accentColor) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(summary.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)

                                ForEach(summary.entries) { entry in
                                    entryRow(entry)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: MacCalendarEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color(for: entry.source))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(timeText(for: entry))
                    Text(entry.sourceName)
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func color(for source: MacCalendarEntrySource) -> Color {
        switch source {
        case .task:
            return appState.accentColor
        case .google:
            return Color.blue.opacity(0.95)
        case .ical:
            return Color.purple.opacity(0.9)
        }
    }

    private func timeText(for entry: MacCalendarEntry) -> String {
        if entry.isAllDay {
            return "All day"
        }
        let start = entry.startDate.formatted(date: .omitted, time: .shortened)
        let end = entry.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

private enum MacCalendarViewMode: String, CaseIterable, Identifiable {
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

private enum MacCalendarEntrySource: String {
    case google
    case ical
    case task
}

private struct MacCalendarEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let source: MacCalendarEntrySource
    let sourceName: String
}

private struct MacCalendarDaySummary: Identifiable {
    let date: Date
    let entries: [MacCalendarEntry]

    var id: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct MacCalendarMonthCell: Identifiable {
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

private enum MacGoogleConnectionState: Equatable {
    case checking
    case unavailable(String)
    case connected(accountCount: Int)
}

@MainActor
private final class MacCalendarViewModel: ObservableObject {
    @Published var selectedMode: MacCalendarViewMode = .week
    @Published var anchorDate: Date = Date()
    @Published private(set) var visibleEntries: [MacCalendarEntry] = []
    @Published private(set) var googleConnectionState: MacGoogleConnectionState = .checking
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?

    private let eventStore = EKEventStore()
    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        return value
    }

    private var taskEntries: [MacCalendarEntry] = []
    private var googleEntries: [MacCalendarEntry] = []
    private var icalEntriesBySubscription: [UUID: [MacCalendarEntry]] = [:]
    private var mergedEntries: [MacCalendarEntry] = []
    private var entriesByDayKey: [String: [MacCalendarEntry]] = [:]
    private var entryCountByDayKey: [String: Int] = [:]
    private var hasTaskByDayKey: Set<String> = []

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

    func setMode(_ mode: MacCalendarViewMode, settings: MaddySettings) {
        guard selectedMode != mode else { return }
        selectedMode = mode
        rebuildVisibleEntries(settings: settings)
    }

    func selectDate(_ date: Date, settings: MaddySettings) {
        anchorDate = date
        rebuildVisibleEntries(settings: settings)
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

    func updateTaskEntries(_ tasks: [TaskItem]) {
        taskEntries = tasks
            .filter { $0.status != .done }
            .compactMap { task in
                guard let dueDate = task.dueDate else { return nil }
                return MacCalendarEntry(
                    id: "task-\(task.id.uuidString)",
                    title: task.title,
                    startDate: dueDate,
                    endDate: dueDate.addingTimeInterval(45 * 60),
                    isAllDay: false,
                    source: .task,
                    sourceName: "Maddy Task"
                )
            }
    }

    func daySummariesForVisiblePeriod() -> [MacCalendarDaySummary] {
        let interval = currentPeriodInterval()
        var summaries: [MacCalendarDaySummary] = []
        var day = calendar.startOfDay(for: interval.start)

        while day < interval.end {
            let key = Self.dayKey(for: day, calendar: calendar)
            if let entries = entriesByDayKey[key], entries.isEmpty == false {
                summaries.append(MacCalendarDaySummary(date: day, entries: entries))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return summaries
    }

    func monthCells() -> [MacCalendarMonthCell] {
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
            return MacCalendarMonthCell(
                date: date,
                isInCurrentMonth: sameMonth,
                entryCount: entryCountByDayKey[key] ?? 0,
                hasTask: hasTaskByDayKey.contains(key)
            )
        }
    }

    func entriesForSelectedDay() -> [MacCalendarEntry] {
        entries(forDay: anchorDate)
    }

    func refreshIfNeeded(
        settings: MaddySettings,
        maxAge: TimeInterval = 120,
        promptCalendarAccess: Bool
    ) async {
        if promptCalendarAccess {
            await refreshAll(settings: settings, promptCalendarAccess: true)
            return
        }

        if let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < maxAge {
            rebuildVisibleEntries(settings: settings)
            return
        }

        await refreshAll(settings: settings, promptCalendarAccess: false)
    }

    func refreshAll(
        settings: MaddySettings,
        promptCalendarAccess: Bool
    ) async {
        guard isRefreshing == false else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefreshAt = Date()
            rebuildVisibleEntries(settings: settings)
        }

        await refreshGoogleEvents(settings: settings, shouldPrompt: promptCalendarAccess)
        await refreshICalEvents(settings: settings)
    }

    func rebuildVisibleEntries(settings: MaddySettings) {
        var result: [MacCalendarEntry] = []
        if settings.showTaskCalendarEntries {
            result.append(contentsOf: taskEntries)
        }
        if settings.showGoogleCalendarEvents {
            result.append(contentsOf: googleEntries)
        }
        if settings.showICalCalendarEvents {
            let enabled = Set(settings.iCalSubscriptions.filter(\.isEnabled).map(\.id))
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

    private func refreshGoogleEvents(settings: MaddySettings, shouldPrompt: Bool) async {
        guard settings.showGoogleCalendarEvents else {
            googleEntries = []
            googleConnectionState = .unavailable("Hidden in Settings")
            return
        }

        let access = await requestEventStoreAccess(shouldPrompt: shouldPrompt)
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
            googleConnectionState = .unavailable("No Google calendars found on this Mac")
            return
        }

        let rangeStart = calendar.date(byAdding: .month, value: -1, to: anchorDate) ?? anchorDate
        let rangeEnd = calendar.date(byAdding: .month, value: 6, to: anchorDate) ?? anchorDate.addingTimeInterval(60 * 60 * 24 * 180)
        let predicate = eventStore.predicateForEvents(withStart: rangeStart, end: rangeEnd, calendars: googleCalendars)
        let events = eventStore.events(matching: predicate)

        googleEntries = events.map { event in
            MacCalendarEntry(
                id: "google-\(event.calendarItemIdentifier)",
                title: event.title?.isEmpty == false ? event.title! : "Untitled Event",
                startDate: event.startDate,
                endDate: max(event.endDate, event.startDate),
                isAllDay: event.isAllDay,
                source: .google,
                sourceName: event.calendar.title
            )
        }
        googleConnectionState = .connected(accountCount: googleCalendars.count)
    }

    private func refreshICalEvents(settings: MaddySettings) async {
        let subscriptions = settings.iCalSubscriptions.filter(\.isEnabled)
        guard subscriptions.isEmpty == false else {
            icalEntriesBySubscription = [:]
            return
        }

        await withTaskGroup(of: MacICalRefreshResult.self) { group in
            for subscription in subscriptions {
                group.addTask {
                    await Self.fetchSubscription(subscription)
                }
            }

            var next: [UUID: [MacCalendarEntry]] = icalEntriesBySubscription
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

    private func entries(forDay date: Date) -> [MacCalendarEntry] {
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

            if #available(macOS 14.0, *) {
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
            return .denied("Calendar permission denied in System Settings")
        @unknown default:
            return .denied("Calendar access unavailable")
        }
    }

    static func subscriptionConfigSignature(_ subscriptions: [ICalSubscription]) -> String {
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

    private static func buildDayCaches(from entries: [MacCalendarEntry], calendar: Calendar)
        -> (entriesByDayKey: [String: [MacCalendarEntry]], entryCountByDayKey: [String: Int], hasTaskByDayKey: Set<String>) {
        var buckets: [String: [MacCalendarEntry]] = [:]
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

private enum MacICalRefreshResult {
    case success(id: UUID, entries: [MacCalendarEntry])
    case failure(id: UUID, message: String)
}

private extension MacCalendarViewModel {
    static func fetchSubscription(_ subscription: ICalSubscription) async -> MacICalRefreshResult {
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
            let entries = parseICal(text: text, subscription: subscription)
            return .success(id: subscription.id, entries: entries)
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

    static func parseICal(text: String, subscription: ICalSubscription) -> [MacCalendarEntry] {
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

        var entries: [MacCalendarEntry] = []
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
                    let baseID = buffer.uid.isEmpty ? "\(buffer.summary)|\(Int(start.timeIntervalSince1970))" : buffer.uid
                    let eventID = "ical-\(subscription.id.uuidString)-\(sanitizeID(baseID))"
                    entries.append(
                        MacCalendarEntry(
                            id: eventID,
                            title: buffer.summary.isEmpty ? "Untitled Event" : buffer.summary,
                            startDate: start,
                            endDate: max(end, start),
                            isAllDay: buffer.allDay,
                            source: .ical,
                            sourceName: subscription.name
                        )
                    )
                }
                inEvent = false
                continue
            }

            guard inEvent, let field = parseField(line) else { continue }
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
