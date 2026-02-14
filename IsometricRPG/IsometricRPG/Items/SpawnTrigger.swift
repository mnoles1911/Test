import CoreGraphics

/// A snapshot of the current game state, passed to spawn triggers for evaluation.
struct GameContext {
    let playerLevel: Int
    let playerHealth: Int
    let playerMaxHealth: Int
    let playerArmor: Int
    let killCount: Int
    let timeElapsed: TimeInterval
    let currentBiome: Biome?
    let playerWorldPosition: CGPoint
    let activeBuffCount: Int
}

/// Defines a condition under which items should spawn and what loot table modifications to apply.
struct SpawnTrigger {
    let name: String
    let condition: (GameContext) -> Bool
    let weightModifiers: [ItemType: Float]  // multipliers on base weight
    let spawnCountBonus: Int                // extra items when triggered

    /// Evaluate whether this trigger fires given the game context.
    func shouldFire(context: GameContext) -> Bool {
        return condition(context)
    }
}

/// Central registry of all spawn triggers. Evaluated when new chunks load.
enum SpawnTriggerRegistry {

    static let allTriggers: [SpawnTrigger] = [
        // Low health → more health potions
        SpawnTrigger(
            name: "LowHealth",
            condition: { ctx in
                let ratio = Float(ctx.playerHealth) / Float(max(ctx.playerMaxHealth, 1))
                return ratio < 0.35
            },
            weightModifiers: [
                .healthPotion: 3.0,
                .healthPotionLarge: 4.0,
                .shieldOrb: 2.0
            ],
            spawnCountBonus: 1
        ),

        // High level → better loot, more specials
        SpawnTrigger(
            name: "HighLevel",
            condition: { ctx in ctx.playerLevel >= 5 },
            weightModifiers: [
                .rareTreasure: 3.0,
                .dungeonKey: 2.5,
                .damageBoost: 1.5,
                .healthPotion: 0.5  // less common basic potions
            ],
            spawnCountBonus: 0
        ),

        // Lots of kills → reward with XP and damage
        SpawnTrigger(
            name: "KillStreak",
            condition: { ctx in ctx.killCount > 0 && ctx.killCount % 10 == 0 },
            weightModifiers: [
                .xpMultiplier: 3.0,
                .damageBoost: 2.0,
                .ammoCache: 2.0
            ],
            spawnCountBonus: 1
        ),

        // Long session → more variety, combat support
        SpawnTrigger(
            name: "LongSession",
            condition: { ctx in ctx.timeElapsed > 120 }, // 2 minutes
            weightModifiers: [
                .speedBoost: 2.0,
                .shieldOrb: 1.5,
                .armorShard: 2.0,
                .ammoCache: 1.5
            ],
            spawnCountBonus: 0
        ),

        // Very long session → rare items start appearing more
        SpawnTrigger(
            name: "VeteranSession",
            condition: { ctx in ctx.timeElapsed > 300 }, // 5 minutes
            weightModifiers: [
                .rareTreasure: 5.0,
                .dungeonKey: 4.0,
                .xpMultiplier: 2.0
            ],
            spawnCountBonus: 1
        ),

        // Dungeon biome → keys and combat items
        SpawnTrigger(
            name: "DungeonBiome",
            condition: { ctx in ctx.currentBiome == .dungeon },
            weightModifiers: [
                .dungeonKey: 5.0,
                .damageBoost: 2.0,
                .healthPotion: 1.5,
                .armorShard: 2.0,
                .rareTreasure: 2.0
            ],
            spawnCountBonus: 1
        ),

        // Desert biome → speed and survival items
        SpawnTrigger(
            name: "DesertBiome",
            condition: { ctx in ctx.currentBiome == .desert },
            weightModifiers: [
                .speedBoost: 2.5,
                .healthPotion: 2.0,
                .healthPotionLarge: 1.5
            ],
            spawnCountBonus: 0
        ),

        // Snow biome → warmth/armor items
        SpawnTrigger(
            name: "SnowBiome",
            condition: { ctx in ctx.currentBiome == .snow },
            weightModifiers: [
                .armorShard: 3.0,
                .shieldOrb: 2.0,
                .healthPotion: 1.5
            ],
            spawnCountBonus: 0
        ),

        // No active buffs → nudge toward powerups
        SpawnTrigger(
            name: "NoBufs",
            condition: { ctx in ctx.activeBuffCount == 0 && ctx.timeElapsed > 30 },
            weightModifiers: [
                .speedBoost: 2.0,
                .damageBoost: 2.0,
                .xpMultiplier: 1.5
            ],
            spawnCountBonus: 0
        ),

        // Full health → fewer potions, more offense
        SpawnTrigger(
            name: "FullHealth",
            condition: { ctx in ctx.playerHealth >= ctx.playerMaxHealth },
            weightModifiers: [
                .healthPotion: 0.2,
                .healthPotionLarge: 0.1,
                .damageBoost: 2.0,
                .xpMultiplier: 1.5,
                .speedBoost: 1.5
            ],
            spawnCountBonus: 0
        )
    ]
}
