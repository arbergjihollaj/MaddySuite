import Foundation

// =====================================================
// MARK: - Achievement
// [TAG: MOBILE_ACHIEVEMENT]
// =====================================================

struct Achievement: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var detail: String
    var icon: String
    var unlockedAt: Date
}
