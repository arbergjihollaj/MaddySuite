//
//  AICommandRouter.swift
//  MaddyV2
//
//  Created by Codex on 04.03.26.
//

import Foundation
import Combine

// =====================================================
// MARK: - AI Command Router
// [TAG: V2_AI_COMMAND_ROUTER]
// =====================================================

@MainActor
final class AICommandRouter: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    enum PendingDueChoice {
        case today
        case tomorrow
        case nextWeek
        case none
    }

    enum RouteResult {
        case success(String)
        case needsDateConfirmation(title: String)
        case failure(String)
    }

    // =====================================================
    // MARK: - Public API
    // [TAG: V2_AI_COMMAND_ROUTER_API]
    // =====================================================

    func route(command raw: String, tasksViewModel: TasksViewModel, defaultPriority: TaskPriority, now: Date = Date()) -> RouteResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .failure("Type a command first.")
        }

        switch parseCommand(trimmed, now: now) {
        case .createTask(let title, let dueDate):
            return createTask(title: title, dueDate: dueDate, tasksViewModel: tasksViewModel, defaultPriority: defaultPriority)

        case .createTaskNeedingDate(let title):
            return .needsDateConfirmation(title: title)

        case .unsupported:
            return .failure("Command not recognized. Try: create task <title> due <date>")
        }
    }

    func resolvePendingDate(
        for title: String,
        choice: PendingDueChoice,
        tasksViewModel: TasksViewModel,
        defaultPriority: TaskPriority,
        now: Date = Date()
    ) -> RouteResult {
        let due: Date?
        switch choice {
        case .today:
            due = GermanDateParser.withHour(now, hour: 18)
        case .tomorrow:
            due = GermanDateParser.withHour(Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now, hour: 18)
        case .nextWeek:
            due = GermanDateParser.withHour(Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now, hour: 18)
        case .none:
            due = nil
        }

        return createTask(title: title, dueDate: due, tasksViewModel: tasksViewModel, defaultPriority: defaultPriority)
    }

    // =====================================================
    // MARK: - Internals
    // [TAG: V2_AI_COMMAND_ROUTER_PARSE]
    // =====================================================

    private enum ParsedCommand {
        case createTask(title: String, dueDate: Date?)
        case createTaskNeedingDate(title: String)
        case unsupported
    }

    private func parseCommand(_ raw: String, now: Date) -> ParsedCommand {
        let lower = raw.lowercased()

        // English command: create task <title> due <date>
        if let english = parseEnglishCreateTask(raw: raw, now: now) {
            return english
        }

        // German intent: ... bis <timephrase> ...
        if lower.contains("bis ") {
            let title = extractGermanTaskTitle(raw)
            guard title.isEmpty == false else { return .unsupported }

            if let due = GermanDateParser.parse(from: raw, now: now) {
                return .createTask(title: title, dueDate: due)
            }
            return .createTaskNeedingDate(title: title)
        }

        return .unsupported
    }

    private func parseEnglishCreateTask(raw: String, now: Date) -> ParsedCommand? {
        let pattern = #"(?i)^\s*create\s+task\s+(.+?)(?:\s+due\s+(.+))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let ns = raw as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: raw, options: [], range: fullRange) else { return nil }

        let title = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else { return .unsupported }

        if match.range(at: 2).location != NSNotFound {
            let dueText = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let dueDate = GermanDateParser.parse(from: dueText, now: now) {
                return .createTask(title: title, dueDate: dueDate)
            }
            return .createTaskNeedingDate(title: title)
        }

        return .createTask(title: title, dueDate: nil)
    }

    private func extractGermanTaskTitle(_ raw: String) -> String {
        let patterns = [
            #"(?i)\bdie\s+(.+?)\s+(erledigen|machen|abschließen|abschliessen)\b"#,
            #"(?i)\bden\s+(.+?)\s+(erledigen|machen|abschließen|abschliessen)\b"#,
            #"(?i)\bdas\s+(.+?)\s+(erledigen|machen|abschließen|abschliessen)\b"#,
            #"(?i)^\s*task\s+(.+)$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = raw as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: raw, options: [], range: range) else { continue }
            let capture = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if capture.isEmpty == false {
                return capture
            }
        }

        // Fallback: remove obvious due-date chunk and helper verbs.
        var cleaned = raw
        if let bisRange = cleaned.range(of: "bis ", options: .caseInsensitive) {
            let prefix = String(cleaned[..<bisRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = String(cleaned[bisRange.upperBound...])
            if let dieRange = suffix.range(of: " die ", options: .caseInsensitive) {
                cleaned = String(suffix[dieRange.upperBound...])
            } else {
                cleaned = prefix.isEmpty ? suffix : prefix
            }
        }

        let junkWords = [
            "ich", "muss", "sollte", "bitte", "erledigen", "machen", "abschließen", "abschliessen"
        ]

        var words = cleaned.split(separator: " ").map(String.init)
        words.removeAll { word in
            junkWords.contains(word.lowercased())
        }

        return words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createTask(title rawTitle: String, dueDate: Date?, tasksViewModel: TasksViewModel, defaultPriority: TaskPriority) -> RouteResult {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else {
            return .failure("Task title is empty.")
        }

        tasksViewModel.resetDraft(defaultPriority: defaultPriority)
        tasksViewModel.draft.title = title
        tasksViewModel.draft.priority = defaultPriority
        tasksViewModel.draft.status = .backlog
        tasksViewModel.draft.dueDate = dueDate

        guard tasksViewModel.saveDraft(defaultPriority: defaultPriority) else {
            return .failure(tasksViewModel.validationMessage ?? "Could not create task.")
        }

        if let dueDate {
            let dueText = dueDate.formatted(date: .abbreviated, time: .shortened)
            return .success("Created task \"\(title)\" due \(dueText).")
        }

        return .success("Created task \"\(title)\".")
    }
}

// =====================================================
// MARK: - German Date Parser
// [TAG: V2_AI_GERMAN_DATE]
// =====================================================

struct GermanDateParser {
    static func parse(from text: String, now: Date = Date()) -> Date? {
        let normalized = normalize(text)

        if normalized.contains("morgen") {
            let date = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
            return withHour(date, hour: 18)
        }

        if normalized.contains("heute") {
            return withHour(now, hour: 18)
        }

        if normalized.contains("naechste woche") || normalized.contains("nächste woche") || normalized.contains("next week") {
            let date = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
            return withHour(date, hour: 18)
        }

        if let explicit = parseExplicitDate(from: text, now: now) {
            return explicit
        }

        if let weekday = weekdayInText(normalized) {
            let forceNextWeek = normalized.contains("naechsten") || normalized.contains("nächsten") || normalized.contains("kommenden")
            return nextWeekday(weekday, from: now, forceNextWeek: forceNextWeek)
        }

        return nil
    }

    static func withHour(_ date: Date, hour: Int) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: components.day,
            hour: hour,
            minute: 0
        )) ?? date
    }

    private static func parseExplicitDate(from text: String, now: Date) -> Date? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let formatters: [DateFormatter] = {
            let formats = ["yyyy-MM-dd", "dd.MM.yyyy", "dd/MM/yyyy", "dd.MM.", "dd/MM"]
            return formats.map { format in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "de_DE")
                formatter.timeZone = .current
                formatter.dateFormat = format
                return formatter
            }
        }()

        for formatter in formatters {
            if let parsed = formatter.date(from: clean) {
                if formatter.dateFormat == "dd.MM." || formatter.dateFormat == "dd/MM" {
                    let calendar = Calendar.current
                    let day = calendar.component(.day, from: parsed)
                    let month = calendar.component(.month, from: parsed)
                    let year = calendar.component(.year, from: now)
                    let candidate = calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? parsed
                    if candidate < now, let nextYear = calendar.date(byAdding: .year, value: 1, to: candidate) {
                        return withHour(nextYear, hour: 18)
                    }
                    return withHour(candidate, hour: 18)
                }
                return withHour(parsed, hour: 18)
            }
        }

        return nil
    }

    private static func weekdayInText(_ normalized: String) -> Int? {
        let map: [(String, Int)] = [
            ("montag", 2), ("monday", 2),
            ("dienstag", 3), ("tuesday", 3),
            ("mittwoch", 4), ("wednesday", 4),
            ("donnerstag", 5), ("thursday", 5),
            ("freitag", 6), ("friday", 6),
            ("samstag", 7), ("sonnabend", 7), ("saturday", 7),
            ("sonntag", 1), ("sunday", 1)
        ]

        for (key, weekday) in map where normalized.contains(key) {
            return weekday
        }
        return nil
    }

    private static func nextWeekday(_ weekday: Int, from now: Date, forceNextWeek: Bool) -> Date? {
        let calendar = Calendar.current
        var components = DateComponents()
        components.weekday = weekday

        guard var next = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTimePreservingSmallerComponents) else {
            return nil
        }

        if forceNextWeek {
            let currentWeek = calendar.component(.weekOfYear, from: now)
            while calendar.component(.weekOfYear, from: next) == currentWeek {
                guard let later = calendar.date(byAdding: .day, value: 7, to: next) else { break }
                next = later
            }
        }

        return withHour(next, hour: 18)
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .lowercased()
    }
}
