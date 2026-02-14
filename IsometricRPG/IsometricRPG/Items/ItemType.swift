import SpriteKit

/// Categories of items that can appear in the world.
enum ItemCategory {
    case consumable    // health potions, buffs
    case weapon        // weapon pickups/upgrades
    case armor         // defense boosts
    case treasure      // XP/score multipliers
    case special       // rare spawns, keys, quest items
}

/// All item types in the game. Each has visual, gameplay, and rarity data.
enum ItemType: CaseIterable {
    case healthPotion
    case healthPotionLarge
    case speedBoost
    case damageBoost
    case shieldOrb
    case ammoCache
    case xpMultiplier
    case armorShard
    case dungeonKey
    case rareTreasure

    var category: ItemCategory {
        switch self {
        case .healthPotion, .healthPotionLarge, .speedBoost: return .consumable
        case .damageBoost, .ammoCache: return .weapon
        case .armorShard, .shieldOrb: return .armor
        case .xpMultiplier: return .treasure
        case .dungeonKey, .rareTreasure: return .special
        }
    }

    var displayName: String {
        switch self {
        case .healthPotion:      return "Health Potion"
        case .healthPotionLarge: return "Large Health Potion"
        case .speedBoost:        return "Speed Boost"
        case .damageBoost:       return "Damage Boost"
        case .shieldOrb:         return "Shield Orb"
        case .ammoCache:         return "Ammo Cache"
        case .xpMultiplier:      return "XP Multiplier"
        case .armorShard:        return "Armor Shard"
        case .dungeonKey:        return "Dungeon Key"
        case .rareTreasure:      return "Rare Treasure"
        }
    }

    /// Base weight for loot tables. Higher = more common.
    var baseWeight: Float {
        switch self {
        case .healthPotion:      return 30
        case .healthPotionLarge: return 10
        case .speedBoost:        return 15
        case .damageBoost:       return 12
        case .shieldOrb:         return 8
        case .ammoCache:         return 20
        case .xpMultiplier:      return 10
        case .armorShard:        return 12
        case .dungeonKey:        return 3
        case .rareTreasure:      return 2
        }
    }

    var color: SKColor {
        switch self {
        case .healthPotion:      return SKColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1)
        case .healthPotionLarge: return SKColor(red: 1.0, green: 0.0, blue: 0.3, alpha: 1)
        case .speedBoost:        return SKColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1)
        case .damageBoost:       return SKColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1)
        case .shieldOrb:         return SKColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1)
        case .ammoCache:         return SKColor(red: 0.9, green: 0.9, blue: 0.2, alpha: 1)
        case .xpMultiplier:      return SKColor(red: 0.8, green: 0.4, blue: 1.0, alpha: 1)
        case .armorShard:        return SKColor(red: 0.6, green: 0.6, blue: 0.7, alpha: 1)
        case .dungeonKey:        return SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1)
        case .rareTreasure:      return SKColor(red: 1.0, green: 0.3, blue: 0.9, alpha: 1)
        }
    }

    var glowColor: SKColor {
        return color.withAlphaComponent(0.3)
    }

    /// Size of the item shape node.
    var size: CGFloat {
        switch category {
        case .special: return 7
        case .weapon: return 6
        default: return 5
        }
    }
}
