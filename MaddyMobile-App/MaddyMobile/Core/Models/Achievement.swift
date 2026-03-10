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
    var tier: RewardTier
    var hidden: Bool
    var rewardTitle: String?
    var rewardCosmetic: String?

    init(
        id: UUID,
        title: String,
        detail: String,
        icon: String,
        unlockedAt: Date,
        tier: RewardTier = .small,
        hidden: Bool = false,
        rewardTitle: String? = nil,
        rewardCosmetic: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.icon = icon
        self.unlockedAt = unlockedAt
        self.tier = tier
        self.hidden = hidden
        self.rewardTitle = rewardTitle
        self.rewardCosmetic = rewardCosmetic
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case icon
        case unlockedAt
        case tier
        case hidden
        case rewardTitle
        case rewardCosmetic
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Achievement"
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "star.fill"
        unlockedAt = try c.decodeIfPresent(Date.self, forKey: .unlockedAt) ?? Date()
        tier = try c.decodeIfPresent(RewardTier.self, forKey: .tier) ?? .small
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        rewardTitle = try c.decodeIfPresent(String.self, forKey: .rewardTitle)
        rewardCosmetic = try c.decodeIfPresent(String.self, forKey: .rewardCosmetic)
    }
}
