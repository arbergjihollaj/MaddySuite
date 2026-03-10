import Foundation

// =====================================================
// MARK: - HabitStore
// [TAG: MOBILE_HABIT_STORE]
// =====================================================

@MainActor
final class HabitStore: ObservableObject {
    struct CloudSnapshot: Codable {
        var habits: [Habit]
        var modifiedAt: Date
    }

    @Published private(set) var habits: [Habit] {
        didSet { persist() }
    }

    var onHabitCompleted: ((Habit) -> Void)?
    var onDataChanged: (() -> Void)?

    private struct Persisted: Codable {
        var habits: [Habit]
        var lastModifiedAt: Date?
    }

    private let storage: LocalJSONStorage
    private let fileName = "habits.json"
    private(set) var lastModifiedAt: Date
    private var isApplyingCloudSnapshot = false
    private var lastStreakDecayDayKey: String?

    init(storage: LocalJSONStorage = .shared) {
        self.storage = storage

        if let loaded = storage.loadIfPresent(Persisted.self, from: fileName) {
            habits = loaded.habits.map(Self.normalized)
            lastModifiedAt = loaded.lastModifiedAt ?? Self.deriveModifiedAt(from: loaded.habits)
        } else {
            let legacy = storage.load([Habit].self, from: fileName, fallback: [])
            habits = legacy.map(Self.normalized)
            lastModifiedAt = Self.deriveModifiedAt(from: legacy)
        }

        persist()
    }

    var todayProgressText: String {
        let planned = scheduledTodayCount
        guard planned > 0 else { return "No habits planned" }
        return "\(completedTodayCount)/\(planned)"
    }

    var scheduledTodayCount: Int {
        habits.filter { isScheduledToday($0) }.count
    }

    var completedTodayCount: Int {
        let key = Self.dayKey(Date())
        return habits.filter { habit in
            isScheduledToday(habit) && (habit.history[key] ?? 0) >= habit.targetValue
        }.count
    }

    func upsert(_ habit: Habit) {
        let normalizedHabit = Self.normalized(habit)
        if let index = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[index] = normalizedHabit
        } else {
            habits.append(normalizedHabit)
        }
        touchLocalMutation()
    }

    func delete(id: UUID) {
        habits.removeAll { $0.id == id }
        touchLocalMutation()
    }

    func markCompleted(id: UUID, date: Date = Date(), allowOffSchedule: Bool = true) {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return }
        var habit = habits[index]
        let key = Self.dayKey(date)

        if allowOffSchedule == false, HabitSchedule.isScheduled(habit, on: date) == false {
            return
        }

        let alreadyComplete = (habit.history[key] ?? 0) >= habit.targetValue
        if alreadyComplete {
            return
        }

        habit.history[key] = habit.targetValue
        updateStreak(for: &habit, on: key)
        habits[index] = habit

        touchLocalMutation()
        onHabitCompleted?(habit)
    }

    func applyStreakDecay(now: Date = Date()) {
        let todayKey = Self.dayKey(now)
        guard lastStreakDecayDayKey != todayKey else { return }
        lastStreakDecayDayKey = todayKey

        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) else { return }
        let yesterdayKey = Self.dayKey(yesterday)

        var changed = false
        for index in habits.indices {
            let scheduledYesterday = HabitSchedule.isScheduled(habits[index], on: yesterday)
            if scheduledYesterday == false {
                continue
            }
            let completedYesterday = (habits[index].history[yesterdayKey] ?? 0) >= habits[index].targetValue
            if completedYesterday == false, habits[index].streak > 0 {
                habits[index].streak = 0
                changed = true
            }
        }

        if changed {
            touchLocalMutation()
        }
    }

    func totalCompletions(forYear year: Int) -> [Date: Int] {
        var map: [Date: Int] = [:]
        let calendar = Calendar.current

        for habit in habits {
            for (key, value) in habit.history {
                guard let date = Self.dayDate(key), calendar.component(.year, from: date) == year else { continue }
                map[date, default: 0] += value
            }
        }

        return map
    }

    func isScheduledToday(_ habit: Habit, now: Date = Date()) -> Bool {
        HabitSchedule.isScheduled(habit, on: now)
    }

    func nextScheduledDate(for habit: Habit, after date: Date = Date()) -> Date? {
        HabitSchedule.nextScheduledDate(for: habit, after: date)
    }

    func cloudSnapshot() -> CloudSnapshot {
        CloudSnapshot(habits: habits, modifiedAt: lastModifiedAt)
    }

    func applyCloudSnapshot(_ snapshot: CloudSnapshot) {
        guard snapshot.modifiedAt > lastModifiedAt else { return }

        isApplyingCloudSnapshot = true
        habits = snapshot.habits.map(Self.normalized)
        lastModifiedAt = snapshot.modifiedAt
        isApplyingCloudSnapshot = false
        persist()
    }

    private func updateStreak(for habit: inout Habit, on key: String) {
        if let last = habit.lastCompletedDateKey,
           let previousDate = Self.dayDate(last),
           let currentDate = Self.dayDate(key) {
            let diff = Calendar.current.dateComponents([.day], from: previousDate, to: currentDate).day ?? 0
            if diff == 1 {
                habit.streak += 1
            } else if diff > 1 {
                habit.streak = 1
            }
        } else {
            habit.streak = max(1, habit.streak)
        }
        habit.lastCompletedDateKey = key
    }

    private func touchLocalMutation() {
        guard isApplyingCloudSnapshot == false else { return }
        lastModifiedAt = Date()
        persist()
        onDataChanged?()
    }

    private func persist() {
        storage.save(Persisted(habits: habits, lastModifiedAt: lastModifiedAt), to: fileName)
    }

    private static func deriveModifiedAt(from habits: [Habit]) -> Date {
        habits
            .flatMap { $0.history.keys }
            .compactMap(Self.dayDate)
            .max() ?? .distantPast
    }

    private static func normalized(_ habit: Habit) -> Habit {
        var copy = habit
        copy.weekdays = HabitSchedule.normalizedWeekdays(copy.weekdays)
        copy.everyXDays = max(1, copy.everyXDays)
        return copy
    }

    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func dayDate(_ key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }
}
