import Foundation
import SpriteKit

/// Item definition for inventory system
struct Item: Codable, Equatable {
    // MARK: - Type & Rarity

    enum ItemType: String, Codable {
        case weapon
        case armor
        case helmet
        case boots
        case ring
        case amulet
        case consumable
        case material

        var slotName: String {
            switch self {
            case .weapon: return "Weapon"
            case .armor: return "Chest"
            case .helmet: return "Helmet"
            case .boots: return "Boots"
            case .ring: return "Ring"
            case .amulet: return "Amulet"
            case .consumable: return "Consumable"
            case .material: return "Material"
            }
        }
    }

    enum Rarity: String, Codable {
        case common
        case uncommon
        case rare
        case legendary

        var color: SKColor {
            switch self {
            case .common: return UITheme.textGray
            case .uncommon: return SKColor.green
            case .rare: return SKColor.blue
            case .legendary: return UITheme.gold
            }
        }

        var displayName: String {
            rawValue.capitalized
        }
    }

    // MARK: - Properties

    let id: String
    let name: String
    let description: String
    let type: ItemType
    let rarity: Rarity

    // Stats (only applicable for equipment)
    var attackBonus: Int = 0
    var defenseBonus: Int = 0
    var healthBonus: Int = 0
    var speedBonus: Int = 0

    // Stack size (for consumables/materials)
    var stackSize: Int = 1
    var maxStackSize: Int = 99

    // MARK: - Computed Properties

    var isEquippable: Bool {
        switch type {
        case .weapon, .armor, .helmet, .boots, .ring, .amulet:
            return true
        case .consumable, .material:
            return false
        }
    }

    var hasStats: Bool {
        return attackBonus > 0 || defenseBonus > 0 || healthBonus > 0 || speedBonus > 0
    }

    // MARK: - Display

    var statsDescription: String {
        var parts: [String] = []
        if attackBonus > 0 { parts.append("+\(attackBonus) ATK") }
        if defenseBonus > 0 { parts.append("+\(defenseBonus) DEF") }
        if healthBonus > 0 { parts.append("+\(healthBonus) HP") }
        if speedBonus > 0 { parts.append("+\(speedBonus) SPD") }
        return parts.isEmpty ? "No bonuses" : parts.joined(separator: ", ")
    }

    // MARK: - Equatable

    static func == (lhs: Item, rhs: Item) -> Bool {
        return lhs.id == rhs.id
    }

    // MARK: - Sample Items (for testing)

    static let sword = Item(
        id: "sword_01",
        name: "Iron Sword",
        description: "A sturdy iron blade forged by skilled blacksmiths.",
        type: .weapon,
        rarity: .common,
        attackBonus: 10,
        defenseBonus: 0,
        healthBonus: 0,
        speedBonus: 0
    )

    static let shield = Item(
        id: "shield_01",
        name: "Wooden Shield",
        description: "A simple wooden shield reinforced with iron bands.",
        type: .armor,
        rarity: .common,
        attackBonus: 0,
        defenseBonus: 8,
        healthBonus: 0,
        speedBonus: 0
    )

    static let helmet = Item(
        id: "helmet_01",
        name: "Leather Helm",
        description: "A leather cap offering basic head protection.",
        type: .helmet,
        rarity: .common,
        attackBonus: 0,
        defenseBonus: 3,
        healthBonus: 0,
        speedBonus: 0
    )

    static let ring = Item(
        id: "ring_01",
        name: "Ring of Strength",
        description: "A magical ring that enhances the wearer's power.",
        type: .ring,
        rarity: .rare,
        attackBonus: 5,
        defenseBonus: 0,
        healthBonus: 0,
        speedBonus: 0
    )

    static let potion = Item(
        id: "potion_health",
        name: "Health Potion",
        description: "Restores 50 HP when consumed.",
        type: .consumable,
        rarity: .common,
        attackBonus: 0,
        defenseBonus: 0,
        healthBonus: 50,
        speedBonus: 0,
        stackSize: 1,
        maxStackSize: 99
    )
}
