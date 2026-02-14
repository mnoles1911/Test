import Foundation

/// Equipment slots for player character
struct Equipment: Codable {
    // MARK: - Slots

    var weapon: Item?
    var armor: Item?
    var helmet: Item?
    var boots: Item?
    var ring1: Item?
    var ring2: Item?
    var amulet: Item?

    // MARK: - Computed Stats

    var totalAttackBonus: Int {
        return [weapon, armor, helmet, boots, ring1, ring2, amulet]
            .compactMap { $0 }
            .reduce(0) { $0 + $1.attackBonus }
    }

    var totalDefenseBonus: Int {
        return [weapon, armor, helmet, boots, ring1, ring2, amulet]
            .compactMap { $0 }
            .reduce(0) { $0 + $1.defenseBonus }
    }

    var totalHealthBonus: Int {
        return [weapon, armor, helmet, boots, ring1, ring2, amulet]
            .compactMap { $0 }
            .reduce(0) { $0 + $1.healthBonus }
    }

    var totalSpeedBonus: Int {
        return [weapon, armor, helmet, boots, ring1, ring2, amulet]
            .compactMap { $0 }
            .reduce(0) { $0 + $1.speedBonus }
    }

    // MARK: - Equip/Unequip

    /// Equip an item to the appropriate slot
    /// Returns the item that was previously equipped in that slot (if any)
    mutating func equip(_ item: Item) -> Item? {
        guard item.isEquippable else { return nil }

        switch item.type {
        case .weapon:
            let old = weapon
            weapon = item
            return old

        case .armor:
            let old = armor
            armor = item
            return old

        case .helmet:
            let old = helmet
            helmet = item
            return old

        case .boots:
            let old = boots
            boots = item
            return old

        case .ring:
            // Equip to first empty ring slot, or replace ring1
            if ring1 == nil {
                ring1 = item
                return nil
            } else if ring2 == nil {
                ring2 = item
                return nil
            } else {
                let old = ring1
                ring1 = item
                return old
            }

        case .amulet:
            let old = amulet
            amulet = item
            return old

        case .consumable, .material:
            return nil // Can't equip these
        }
    }

    /// Unequip an item from a specific slot
    /// Returns the unequipped item (if any)
    mutating func unequip(slot: EquipmentSlot) -> Item? {
        switch slot {
        case .weapon:
            let item = weapon
            weapon = nil
            return item

        case .armor:
            let item = armor
            armor = nil
            return item

        case .helmet:
            let item = helmet
            helmet = nil
            return item

        case .boots:
            let item = boots
            boots = nil
            return item

        case .ring1:
            let item = ring1
            ring1 = nil
            return item

        case .ring2:
            let item = ring2
            ring2 = nil
            return item

        case .amulet:
            let item = amulet
            amulet = nil
            return item
        }
    }

    /// Get item in a specific slot
    func getItem(slot: EquipmentSlot) -> Item? {
        switch slot {
        case .weapon: return weapon
        case .armor: return armor
        case .helmet: return helmet
        case .boots: return boots
        case .ring1: return ring1
        case .ring2: return ring2
        case .amulet: return amulet
        }
    }

    // MARK: - Slot Enum

    enum EquipmentSlot: String, CaseIterable, Codable {
        case weapon
        case armor
        case helmet
        case boots
        case ring1
        case ring2
        case amulet

        var displayName: String {
            switch self {
            case .weapon: return "Weapon"
            case .armor: return "Chest"
            case .helmet: return "Helmet"
            case .boots: return "Boots"
            case .ring1: return "Ring 1"
            case .ring2: return "Ring 2"
            case .amulet: return "Amulet"
            }
        }
    }
}
