import Foundation

/// Player data model for stats, inventory, and equipment
/// This structure can be saved/loaded via SaveManager
struct PlayerData: Codable {
    // MARK: - Basic Stats

    var level: Int
    var experience: Int
    var experienceToNext: Int
    var health: Int
    var maxHealth: Int

    // MARK: - Extended Stats (for future use)

    var attack: Int = 10
    var defense: Int = 5
    var speed: Int = 150
    var criticalChance: Float = 0.15 // 15%

    // MARK: - Inventory & Equipment (placeholders for Phase 3)

    // var inventory: [Item] = []
    // var equipment: Equipment? = nil

    // MARK: - Progression

    var killCount: Int = 0

    // MARK: - Initialization

    init(level: Int = 1, experience: Int = 0, health: Int = 100) {
        self.level = level
        self.experience = experience
        self.experienceToNext = PlayerData.calculateExperienceForLevel(level + 1)
        self.health = health
        self.maxHealth = 100 + (level - 1) * 10
    }

    // MARK: - Level Calculation

    static func calculateExperienceForLevel(_ level: Int) -> Int {
        // Experience required grows by 1.5x each level
        return Int(100 * pow(1.5, Double(level - 1)))
    }

    // MARK: - Stat Calculations

    /// Total attack including equipment bonuses (placeholder)
    var totalAttack: Int {
        // In Phase 3, this will include equipment bonuses
        return attack
    }

    /// Total defense including equipment bonuses (placeholder)
    var totalDefense: Int {
        // In Phase 3, this will include equipment bonuses
        return defense
    }

    // MARK: - Default Player

    static var `default`: PlayerData {
        return PlayerData(level: 1, experience: 0, health: 100)
    }
}
