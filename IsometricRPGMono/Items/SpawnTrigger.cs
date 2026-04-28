namespace IsometricRPG;

/// <summary>
/// Shared game context passed to spawn trigger conditions and lore unlock checks.
/// Defined once here; LoreEntry.cs references this type.
/// </summary>
public struct GameContext
{
    public int PlayerLevel          { get; set; }
    public int ChunksExplored       { get; set; }
    public int EnemiesKilled        { get; set; }
    public int ItemsCollected       { get; set; }
    public bool BossDefeated        { get; set; }
    public List<string> Flags       { get; set; }

    public GameContext()
    {
        PlayerLevel    = 1;
        ChunksExplored = 0;
        EnemiesKilled  = 0;
        ItemsCollected = 0;
        BossDefeated   = false;
        Flags          = new List<string>();
    }

    public bool HasFlag(string flag) => Flags.Contains(flag);
}

/// <summary>
/// Defines a conditional item-spawn rule with optional weight modifiers.
/// </summary>
public class SpawnTrigger
{
    public string Id                              { get; set; }
    public string Description                     { get; set; }
    public Func<GameContext, bool> Condition      { get; set; }
    public Dictionary<ItemType, float> WeightModifiers { get; set; }
    public bool OneShot                           { get; set; }

    public SpawnTrigger(
        string id,
        string description,
        Func<GameContext, bool> condition,
        Dictionary<ItemType, float>? weightModifiers = null,
        bool oneShot = false)
    {
        Id               = id;
        Description      = description;
        Condition        = condition;
        WeightModifiers  = weightModifiers ?? new Dictionary<ItemType, float>();
        OneShot          = oneShot;
    }

    public bool Evaluate(GameContext context) => Condition(context);
}

/// <summary>
/// Central registry of all spawn triggers.
/// </summary>
public static class SpawnTriggerRegistry
{
    public static readonly List<SpawnTrigger> All = new List<SpawnTrigger>
    {
        new SpawnTrigger(
            id:          "early_game_health",
            description: "Extra health potions at the start",
            condition:   ctx => ctx.PlayerLevel <= 3,
            weightModifiers: new Dictionary<ItemType, float>
            {
                { ItemType.HealthPotion, 2.0f }
            }),

        new SpawnTrigger(
            id:          "boss_treasure",
            description: "Rare loot after defeating the boss",
            condition:   ctx => ctx.BossDefeated,
            weightModifiers: new Dictionary<ItemType, float>
            {
                { ItemType.Artifact, 3.0f },
                { ItemType.Gem,      2.0f }
            },
            oneShot: true),

        new SpawnTrigger(
            id:          "explorer_bonus",
            description: "Bonus materials for avid explorers",
            condition:   ctx => ctx.ChunksExplored >= 10,
            weightModifiers: new Dictionary<ItemType, float>
            {
                { ItemType.Iron,    1.5f },
                { ItemType.Leather, 1.5f }
            }),

        new SpawnTrigger(
            id:          "veteran_weapons",
            description: "Better weapons for experienced fighters",
            condition:   ctx => ctx.EnemiesKilled >= 50,
            weightModifiers: new Dictionary<ItemType, float>
            {
                { ItemType.Sword, 2.0f },
                { ItemType.Axe,   2.0f },
                { ItemType.Bow,   1.5f }
            }),

        new SpawnTrigger(
            id:          "quest_item_unlock",
            description: "Quest items appear once a flag is set",
            condition:   ctx => ctx.HasFlag("ancient_ruins_found"),
            weightModifiers: new Dictionary<ItemType, float>
            {
                { ItemType.AncientKey,   4.0f },
                { ItemType.CrystalShard, 3.0f }
            }),
    };

    public static List<SpawnTrigger> GetActive(GameContext context)
    {
        return All.Where(t => t.Evaluate(context)).ToList();
    }

    public static Dictionary<ItemType, float> BuildWeightTable(GameContext context)
    {
        var table = new Dictionary<ItemType, float>();
        foreach (var trigger in GetActive(context))
        {
            foreach (var (itemType, weight) in trigger.WeightModifiers)
            {
                if (table.ContainsKey(itemType))
                    table[itemType] += weight;
                else
                    table[itemType] = weight;
            }
        }
        return table;
    }
}
