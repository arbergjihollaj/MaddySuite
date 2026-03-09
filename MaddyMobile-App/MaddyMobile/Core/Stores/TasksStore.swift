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
        tasks.filter { $0.status != .done }.count
    }

    func tasks(for status: TaskStatus) -> [TaskItem] {
        tasks.filter { $0.status == status }
            .sorted { lhs, rhs in
                if lhs.dueDate == nil && rhs.dueDate != nil { return false }
                if lhs.dueDate != nil && rhs.dueDate == nil { return true }
                return (lhs.dueDate ?? lhs.createdAt) < (rhs.dueDate ?? rhs.createdAt)
            }
    }

    func upsert(_ task: TaskItem) {
        var next = task
        next.updatedAt = Date()

        if next.status == .done {
            archive(task: next, triggerRewards: true)
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
            archive(task: item, triggerRewards: true)
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

    private func archive(task: TaskItem, triggerRewards: Bool) {
        var doneTask = task
        doneTask.status = .done
        doneTask.completedAt = Date()
        doneTask.updatedAt = Date()

        tasks.removeAll { $0.id == doneTask.id }
        archivedTasks.insert(
            ArchivedTaskItem(id: UUID(), task: doneTask, archivedAt: Date()),
            at: 0
        )

        touchLocalMutation()
        if triggerRewards {
            onTaskArchived?(doneTask)
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
