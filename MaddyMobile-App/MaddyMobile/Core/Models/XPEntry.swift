import Foundation

// =====================================================
// MARK: - XPEntry
// [TAG: MOBILE_XP_ENTRY]
// =====================================================

struct XPEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date
    var delta: Int
    var totalXP: Int
    var level: Int
    var reason: String
}
