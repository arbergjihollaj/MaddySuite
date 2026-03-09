import Foundation

// =====================================================
// MARK: - Gamification Models
// [TAG: MOBILE_GAMIFICATION_MODEL]
// =====================================================

enum SkillCategory: String, Codable, CaseIterable, Identifiable {
    case focus
    case consistency
    case discipline
    case health
    case learning
    case creativity

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

struct SkillValues: Codable, Equatable {
    var focus: Int
    var consistency: Int
    var discipline: Int
    var health: Int
    var learning: Int
    var creativity: Int

    static let zero = SkillValues(focus: 0, consistency: 0, discipline: 0, health: 0, learning: 0, creativity: 0)

    subscript(category: SkillCategory) -> Int {
        get {
            switch category {
            case .focus: return focus
            case .consistency: return consistency
            case .discipline: return discipline
            case .health: return health
            case .learning: return learning
            case .creativity: return creativity
            }
        }
        set {
            let safe = max(0, min(100, newValue))
            switch category {
            case .focus: focus = safe
            case .consistency: consistency = safe
            case .discipline: discipline = safe
            case .health: health = safe
            case .learning: learning = safe
            case .creativity: creativity = safe
            }
        }
    }
}

struct DailyChallenge: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var completed: Bool
}
