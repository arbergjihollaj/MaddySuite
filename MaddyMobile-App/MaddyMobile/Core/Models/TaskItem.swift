import Foundation

// =====================================================
// MARK: - Task Models
// [TAG: MOBILE_TASK_MODEL]
// =====================================================

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case backlog
    case inProgress
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backlog: return "Backlog"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }
}

struct TaskItem: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var dueDate: Date?
    var tags: [String]
    var status: TaskStatus
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    static func empty() -> TaskItem {
        let now = Date()
        return TaskItem(
            id: UUID(),
            title: "",
            dueDate: nil,
            tags: [],
            status: .backlog,
            createdAt: now,
            updatedAt: now,
            completedAt: nil
        )
    }
}

struct ArchivedTaskItem: Identifiable, Codable, Equatable {
    var id: UUID
    var task: TaskItem
    var archivedAt: Date
}
