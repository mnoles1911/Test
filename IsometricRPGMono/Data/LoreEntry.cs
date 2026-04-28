using System.Text.Json.Serialization;

namespace IsometricRPG;

public enum LoreCategory
{
    World,
    Bestiary,
    History,
    Characters,
    Items,
    Locations
}

public static class LoreCategoryExtensions
{
    public static string Icon(this LoreCategory category)
    {
        return category switch
        {
            LoreCategory.World      => "globe",
            LoreCategory.Bestiary   => "monster",
            LoreCategory.History    => "scroll",
            LoreCategory.Characters => "person",
            LoreCategory.Items      => "item",
            LoreCategory.Locations  => "map",
            _                       => "unknown"
        };
    }

    public static string DisplayName(this LoreCategory category)
    {
        return category switch
        {
            LoreCategory.World      => "World",
            LoreCategory.Bestiary   => "Bestiary",
            LoreCategory.History    => "History",
            LoreCategory.Characters => "Characters",
            LoreCategory.Items      => "Items",
            LoreCategory.Locations  => "Locations",
            _                       => "Unknown"
        };
    }
}

public class LoreEntry
{
    [JsonInclude]
    public string Id          { get; set; } = string.Empty;

    [JsonInclude]
    public string Title       { get; set; } = string.Empty;

    [JsonInclude]
    public string Body        { get; set; } = string.Empty;

    [JsonInclude]
    public LoreCategory Category { get; set; }

    [JsonInclude]
    public bool IsUnlocked    { get; set; } = false;

    /// <summary>
    /// Optional condition: if non-null, entry unlocks when the condition returns true.
    /// Not serialized — rebuilt at runtime.
    /// </summary>
    [JsonIgnore]
    public Func<GameContext, bool>? UnlockCondition { get; set; }

    public LoreEntry() { }

    public LoreEntry(
        string id,
        string title,
        string body,
        LoreCategory category,
        Func<GameContext, bool>? unlockCondition = null)
    {
        Id               = id;
        Title            = title;
        Body             = body;
        Category         = category;
        IsUnlocked       = false;
        UnlockCondition  = unlockCondition;
    }

    /// <summary>
    /// Returns true when this entry's unlock condition is satisfied by the given context,
    /// or if no condition is defined (always visible once encountered).
    /// </summary>
    public bool ShouldUnlock(GameContext context)
    {
        if (UnlockCondition == null) return true;
        return UnlockCondition(context);
    }

    // -------------------------------------------------------------------------
    // Sample entries
    // -------------------------------------------------------------------------
    public static readonly List<LoreEntry> SampleEntries = new List<LoreEntry>
    {
        new LoreEntry(
            id:       "world_overview",
            title:    "The Shattered Realm",
            body:     "Long ago, the realm was whole. The Sundering cracked it into countless floating islands, " +
                      "each drifting through an eternal twilight sky. Survivors built anew on the fragments.",
            category: LoreCategory.World),

        new LoreEntry(
            id:       "goblin_entry",
            title:    "Goblin",
            body:     "Small, cunning creatures that infest ruins and dark forests. " +
                      "Individually weak, they are dangerous in numbers.",
            category: LoreCategory.Bestiary,
            unlockCondition: ctx => ctx.EnemiesKilled >= 1),

        new LoreEntry(
            id:       "ancient_war",
            title:    "The Ancient War",
            body:     "Three hundred years before the Sundering, two great civilisations clashed. " +
                      "Their weapons of mass destruction ultimately tore the world apart.",
            category: LoreCategory.History,
            unlockCondition: ctx => ctx.ChunksExplored >= 5),

        new LoreEntry(
            id:       "the_warden",
            title:    "The Warden",
            body:     "A titanic construct forged in the final days of the old world, " +
                      "tasked with guarding a secret that could restore — or destroy — the realm.",
            category: LoreCategory.Characters,
            unlockCondition: ctx => ctx.BossDefeated),

        new LoreEntry(
            id:       "crystal_shard_lore",
            title:    "Crystal Shard",
            body:     "Fragments of the World Crystal, shattered during the Sundering. " +
                      "Each piece hums with residual power and is sought by scholars and warlords alike.",
            category: LoreCategory.Items,
            unlockCondition: ctx => ctx.ItemsCollected >= 10),

        new LoreEntry(
            id:       "sunken_city",
            title:    "The Sunken City",
            body:     "Once the grandest metropolis in the known world, it now lies half-submerged " +
                      "beneath a permanent fog bank. Treasure hunters rarely return.",
            category: LoreCategory.Locations,
            unlockCondition: ctx => ctx.HasFlag("ancient_ruins_found")),
    };
}
