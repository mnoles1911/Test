import Foundation

/// Lore entry for the codex/library system
struct LoreEntry: Codable, Identifiable {
    // MARK: - Properties

    let id: String
    let title: String
    let description: String
    let category: Category
    var isUnlocked: Bool = false

    // MARK: - Category

    enum Category: String, Codable, CaseIterable {
        case enemies = "Enemies"
        case items = "Items"
        case lore = "Lore"
        case world = "World"

        var displayName: String {
            return rawValue
        }

        var icon: String {
            switch self {
            case .enemies: return "💀"
            case .items: return "⚔️"
            case .lore: return "📜"
            case .world: return "🗺️"
            }
        }
    }

    // MARK: - Sample Entries

    static let sampleEntries: [LoreEntry] = [
        // Enemies
        LoreEntry(
            id: "enemy_shadow_fiend",
            title: "Shadow Fiend",
            description: "A creature of darkness that hunts in the night. These malevolent beings are drawn to sources of light and life, seeking to extinguish them. They grow stronger the farther from the realm's center they roam.",
            category: .enemies,
            isUnlocked: false
        ),
        LoreEntry(
            id: "enemy_goblin",
            title: "Goblin Scout",
            description: "Small but cunning creatures that infest the dungeons. They work in packs and are known for their cowardice when alone, but ferocity in numbers.",
            category: .enemies,
            isUnlocked: false
        ),

        // Items
        LoreEntry(
            id: "item_health_potion",
            title: "Health Potion",
            description: "A red vial containing a healing elixir brewed by ancient alchemists. Restores vitality when consumed. The recipe has been passed down through generations of healers.",
            category: .items,
            isUnlocked: false
        ),
        LoreEntry(
            id: "item_iron_sword",
            title: "Iron Sword",
            description: "A sturdy blade forged by skilled blacksmiths. While basic, it is reliable and effective against most foes. The mark of the forge is stamped on its hilt.",
            category: .items,
            isUnlocked: false
        ),

        // Lore
        LoreEntry(
            id: "lore_realm_of_shadows",
            title: "The Realm of Shadows",
            description: "Long ago, this land was prosperous and full of light. But a great calamity befell the kingdom, plunging it into eternal twilight. Now, only the bravest adventurers dare venture into its depths, seeking lost treasures and forgotten knowledge.",
            category: .lore,
            isUnlocked: true // Starting lore
        ),
        LoreEntry(
            id: "lore_ancient_ruins",
            title: "Ancient Ruins",
            description: "Scattered throughout the realm are remnants of a civilization that predates even the oldest records. Their purpose remains a mystery, but the dungeons they left behind are filled with both danger and treasure.",
            category: .lore,
            isUnlocked: false
        ),

        // World
        LoreEntry(
            id: "world_grasslands",
            title: "The Grasslands",
            description: "The safest region of the realm, where grass grows and the shadows are weakest. Most adventurers begin their journey here before venturing into more dangerous territories.",
            category: .world,
            isUnlocked: true // Starting area
        ),
        LoreEntry(
            id: "world_dungeons",
            title: "Forgotten Dungeons",
            description: "Labyrinths carved into the earth by unknown hands. Their corridors twist and turn, filled with traps, treasures, and creatures that have made the darkness their home.",
            category: .world,
            isUnlocked: false
        ),
        LoreEntry(
            id: "world_desert",
            title: "The Scorched Wastes",
            description: "A barren desert where little survives. The sun beats down mercilessly during the day, while frigid winds sweep across the dunes at night. Only the hardiest creatures call this place home.",
            category: .world,
            isUnlocked: false
        )
    ]

    // MARK: - Unlock Conditions

    /// Check if this entry should unlock based on game context
    func shouldUnlock(context: GameContext) -> Bool {
        // Already unlocked
        if isUnlocked { return false }

        // Unlock conditions based on entry ID
        switch id {
        case "enemy_shadow_fiend":
            return context.killCount >= 1
        case "enemy_goblin":
            return context.killCount >= 5

        case "item_health_potion":
            return context.playerHealth < context.playerMaxHealth
        case "item_iron_sword":
            return context.playerLevel >= 2

        case "lore_ancient_ruins":
            return context.killCount >= 10
        case "world_dungeons":
            return context.currentBiome == .dungeon
        case "world_desert":
            return context.currentBiome == .desert

        default:
            return false
        }
    }
}

/// Game context for determining unlock conditions
struct GameContext {
    let playerLevel: Int
    let playerHealth: Int
    let playerMaxHealth: Int
    let playerArmor: Int
    let killCount: Int
    let timeElapsed: TimeInterval
    let currentBiome: BiomeType?
    let playerWorldPosition: CGPoint
    let activeBuffCount: Int
}
