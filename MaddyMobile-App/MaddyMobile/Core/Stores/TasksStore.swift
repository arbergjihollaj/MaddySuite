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
        return archivedTasks.map(\.task).filter { $0.isDailyTask && $0.effectiveDailyKey == dayKey }
    }

    func completedNormalTasksCount(for date: Date = Date()) -> Int {
        let calendar = Calendar.current
        return archivedTasks.reduce(into: 0) { partial, entry in
            guard entry.task.isDailyTask == false else { return }
            guard let completed = entry.task.completedAt else { return }
            guard calendar.isDate(completed, inSameDayAs: date) else { return }
            partial += 1
        }
    }

    func upsert(_ task: TaskItem) {
        var next = task
        next.updatedAt = Date()

        if next.isDailyTask, next.dailyDateKey == nil {
            next.dailyDateKey = TaskItem.dayKey(Date())
        }

        if next.status == .done {
            queueArchive(taskID: next.id, fallback: next, triggerRewards: true)
            return
        }

        if let index = tasks.firstIndex(where: { $0.id == next.id }) {
            tasks[index] = next
        } else {
            tasks.append(next)
        }

        touchLocalMutation()
    }

    func delete(id: UUID) {
        tasks.removeAll { $0.id == id }
        archivedTasks.removeAll { $0.task.id == id }
        touchLocalMutation()
    }

    func moveToStatus(taskID: UUID, status: TaskStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        var item = tasks[index]
        item.status = status
        item.updatedAt = Date()

        if status == .done {
            queueArchive(taskID: item.id, fallback: item, triggerRewards: true)
        } else {
            tasks[index] = item
            touchLocalMutation()
        }
    }

    func restoreArchived(id: UUID) {
        guard let archivedIndex = archivedTasks.firstIndex(where: { $0.id == id }) else { return }
        var item = archivedTasks[archivedIndex].task
        item.status = .backlog
        item.completedAt = nil
        item.updatedAt = Date()

        archivedTasks.remove(at: archivedIndex)
        tasks.append(item)
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

    private func queueArchive(taskID: UUID, fallback: TaskItem, triggerRewards: Bool) {
        // Deferring the destructive remove->archive transition avoids list mutation crashes
        // when the user marks a task done from active swipe/UI transactions.
        Task { @MainActor [weak self] in
            self?.archive(taskID: taskID, fallback: fallback, triggerRewards: triggerRewards)
        }
    }

    private func archive(taskID: UUID, fallback: TaskItem, triggerRewards: Bool) {
        guard archivedTasks.contains(where: { $0.task.id == taskID }) == false else { return }

        var source = tasks.first(where: { $0.id == taskID }) ?? fallback
        source.status = .done
        source.completedAt = source.completedAt ?? Date()
        source.updatedAt = Date()

        tasks.removeAll { $0.id == source.id }
        archivedTasks.insert(
            ArchivedTaskItem(id: UUID(), task: source, archivedAt: Date()),
            at: 0
        )

        touchLocalMutation()
        if triggerRewards {
            onTaskArchived?(source)
            onTaskCompleted?(source, completedNormalTasksCount())
        }
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
