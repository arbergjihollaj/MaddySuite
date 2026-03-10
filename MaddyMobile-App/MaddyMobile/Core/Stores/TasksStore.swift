import Foundation

// =====================================================
// MARK: - TasksStore
// [TAG: MOBILE_TASKS_STORE]
// =====================================================

@MainActor
final class TasksStore: ObservableObject {
    struct CloudSnapshot: Codable {
        var tasks: [TaskItem]
        var archivedTasks: [ArchivedTaskItem]
        var modifiedAt: Date
    }

    @Published private(set) var tasks: [TaskItem] {
        didSet { persist() }
    }

    @Published private(set) var archivedTasks: [ArchivedTaskItem] {
        didSet { persist() }
    }

    var onTaskArchived: ((TaskItem) -> Void)?
    var onTaskCompleted: ((TaskItem, Int) -> Void)?
    var onDailyTaskMissed: ((TaskItem) -> Void)?
    var onDataChanged: (() -> Void)?

    private struct Persisted: Codable {
        var tasks: [TaskItem]
        var archivedTasks: [ArchivedTaskItem]
        var lastModifiedAt: Date?
    }

    private let storage: LocalJSONStorage
    private let fileName = "tasks.json"
    private(set) var lastModifiedAt: Date
    private var isApplyingCloudSnapshot = false

    init(storage: LocalJSONStorage = .shared) {
        self.storage = storage

        if let loaded = storage.loadIfPresent(Persisted.self, from: fileName) {
            tasks = loaded.tasks
            archivedTasks = loaded.archivedTasks
            lastModifiedAt = loaded.lastModifiedAt ?? Self.deriveModifiedAt(tasks: loaded.tasks, archived: loaded.archivedTasks)
        } else {
            tasks = []
            archivedTasks = []
            lastModifiedAt = .distantPast
        }

        persist()
    }

    var openCount: Int {
        tasks.filter { $0.status != .done && $0.status != .missed }.count
    }

    var doneCount: Int {
        var ids = Set<UUID>()
        for task in tasks where task.status == .done {
            ids.insert(task.id)
        }
        for task in archivedTasks.map(\.task) where task.status == .done {
            ids.insert(task.id)
        }
        return ids.count
    }

    func tasks(for status: TaskStatus) -> [TaskItem] {
        tasks
            .filter { $0.status == status }
            .sorted { lhs, rhs in
                if lhs.isDailyTask != rhs.isDailyTask {
                    return lhs.isDailyTask && rhs.isDailyTask == false
                }
                if lhs.dueDate == nil && rhs.dueDate != nil { return false }
                if lhs.dueDate != nil && rhs.dueDate == nil { return true }
                return (lhs.dueDate ?? lhs.createdAt) < (rhs.dueDate ?? rhs.createdAt)
            }
    }

    func dailyTasks(for date: Date = Date()) -> [TaskItem] {
        let dayKey = TaskItem.dayKey(date)
        return tasks.filter { $0.isDailyTask && $0.effectiveDailyKey == dayKey && $0.status != .done }
    }

    func completedDailyTasks(for date: Date = Date()) -> [TaskItem] {
        let dayKey = TaskItem.dayKey(date)
        var combined: [UUID: TaskItem] = [:]
        for task in tasks where task.isDailyTask && task.effectiveDailyKey == dayKey && task.status == .done {
            combined[task.id] = task
        }
        for task in archivedTasks.map(\.task) where task.isDailyTask && task.effectiveDailyKey == dayKey && task.status == .done {
            combined[task.id] = task
        }
        return combined.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func completedNormalTasksCount(for date: Date = Date()) -> Int {
        let calendar = Calendar.current
        var seen = Set<UUID>()
        let activeDone = tasks.reduce(into: 0) { partial, task in
            guard task.status == .done else { return }
            guard task.isDailyTask == false else { return }
            guard let completed = task.completedAt else { return }
            guard calendar.isDate(completed, inSameDayAs: date) else { return }
            guard seen.insert(task.id).inserted else { return }
            partial += 1
        }
        let archivedDone = archivedTasks.reduce(into: 0) { partial, entry in
            let task = entry.task
            guard task.status == .done else { return }
            guard task.isDailyTask == false else { return }
            guard let completed = task.completedAt else { return }
            guard calendar.isDate(completed, inSameDayAs: date) else { return }
            guard seen.insert(task.id).inserted else { return }
            partial += 1
        }
        return activeDone + archivedDone
    }

    func upsert(_ task: TaskItem) {
        var next = task
        next.updatedAt = Date()

        if next.isDailyTask, next.dailyDateKey == nil {
            next.dailyDateKey = TaskItem.dayKey(Date())
        }
        let previous = tasks.first(where: { $0.id == next.id })
        if next.status == .done {
            next.completedAt = next.completedAt ?? Date()
        } else {
            next.completedAt = nil
        }

        if let index = tasks.firstIndex(where: { $0.id == next.id }) {
            tasks[index] = next
        } else {
            tasks.append(next)
        }

        touchLocalMutation()
        if previous?.status != .done, next.status == .done {
            onTaskCompleted?(next, completedNormalTasksCount())
        }
    }

    func delete(id: UUID) {
        tasks.removeAll { $0.id == id }
        archivedTasks.removeAll { $0.task.id == id }
        touchLocalMutation()
    }

    func moveToStatus(taskID: UUID, status: TaskStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        var item = tasks[index]
        let wasDone = item.status == .done
        item.status = status
        item.updatedAt = Date()
        if status == .done {
            item.completedAt = item.completedAt ?? Date()
        } else {
            item.completedAt = nil
        }
        tasks[index] = item
        touchLocalMutation()
        if wasDone == false, status == .done {
            onTaskCompleted?(item, completedNormalTasksCount())
        }
    }

    @discardableResult
    func archive(taskID: UUID) -> ArchivedTaskItem? {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return nil }
        var item = tasks.remove(at: index)
        item.updatedAt = Date()

        if let existingArchiveIndex = archivedTasks.firstIndex(where: { $0.task.id == taskID }) {
            archivedTasks.remove(at: existingArchiveIndex)
        }

        let archived = ArchivedTaskItem(id: UUID(), task: item, archivedAt: Date())
        archivedTasks.insert(archived, at: 0)
        touchLocalMutation()
        onTaskArchived?(item)
        return archived
    }

    func restoreArchived(id: UUID) {
        guard let archivedIndex = archivedTasks.firstIndex(where: { $0.id == id }) else { return }
        var item = archivedTasks[archivedIndex].task
        if item.status == .missed {
            item.status = .backlog
            item.completedAt = nil
        }
        item.updatedAt = Date()

        archivedTasks.remove(at: archivedIndex)
        if let activeIndex = tasks.firstIndex(where: { $0.id == item.id }) {
            tasks[activeIndex] = item
        } else {
            tasks.append(item)
        }
        touchLocalMutation()
    }

    func applyDailyRollover(now: Date = Date()) {
        let currentDayKey = TaskItem.dayKey(now)
        let previousDaily = tasks.filter { $0.isDailyTask && $0.effectiveDailyKey != currentDayKey && $0.status != .done }

        guard previousDaily.isEmpty == false else { return }

        for task in previousDaily {
            var missed = task
            missed.status = .missed
            missed.updatedAt = now
            tasks.removeAll { $0.id == missed.id }
            archivedTasks.insert(ArchivedTaskItem(id: UUID(), task: missed, archivedAt: now), at: 0)
            onDailyTaskMissed?(missed)
        }

        touchLocalMutation()
    }

    func ensureDailyTaskCapacity(count: Int, templates: [TaskItem] = [], date: Date = Date()) {
        let dayKey = TaskItem.dayKey(date)
        let currentDaily = tasks.filter { $0.isDailyTask && $0.effectiveDailyKey == dayKey && $0.status != .done }
        let needed = max(0, count - currentDaily.count)
        guard needed > 0 else { return }

        var generated: [TaskItem] = []
        if templates.isEmpty == false {
            for template in templates.prefix(needed) {
                var daily = template
                daily.id = UUID()
                daily.status = .backlog
                daily.dailyDateKey = dayKey
                daily.createdAt = date
                daily.updatedAt = date
                generated.append(daily)
            }
        }

        let existingTitles = Set((currentDaily + generated).map { $0.title.lowercased() })
        let fallback = DailyTaskLibrary.tasks(
            pack: nil,
            count: max(0, needed - generated.count),
            dayKey: dayKey,
            date: date,
            excludingTitles: existingTitles
        )
        generated.append(contentsOf: fallback)

        while generated.count < needed {
            let refill = DailyTaskLibrary.tasks(
                pack: nil,
                count: 1,
                dayKey: dayKey,
                date: date
            )
            guard let extra = refill.first else { break }
            generated.append(extra)
        }

        tasks.append(contentsOf: generated)
        touchLocalMutation()
    }

    func cloudSnapshot() -> CloudSnapshot {
        CloudSnapshot(tasks: tasks, archivedTasks: archivedTasks, modifiedAt: lastModifiedAt)
    }

    func applyCloudSnapshot(_ snapshot: CloudSnapshot) {
        guard snapshot.modifiedAt > lastModifiedAt else { return }

        isApplyingCloudSnapshot = true
        tasks = snapshot.tasks
        archivedTasks = snapshot.archivedTasks
        lastModifiedAt = snapshot.modifiedAt
        isApplyingCloudSnapshot = false
        persist()
    }

    private func touchLocalMutation() {
        guard isApplyingCloudSnapshot == false else { return }
        lastModifiedAt = Date()
        persist()
        onDataChanged?()
    }

    private func persist() {
        storage.save(
            Persisted(tasks: tasks, archivedTasks: archivedTasks, lastModifiedAt: lastModifiedAt),
            to: fileName
        )
    }

    private static func deriveModifiedAt(tasks: [TaskItem], archived: [ArchivedTaskItem]) -> Date {
        let taskMax = tasks.map(\.updatedAt).max() ?? .distantPast
        let archiveMax = archived.map(\.archivedAt).max() ?? .distantPast
        return max(taskMax, archiveMax)
    }
}
