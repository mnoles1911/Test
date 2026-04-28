using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace IsometricRPG;

/// <summary>
/// Responsible for placing WorldItems into newly loaded chunks and managing
/// item attraction / collection near the player.
/// </summary>
public class ItemSpawner
{
    private readonly List<WorldItem> _items = new List<WorldItem>();

    public IReadOnlyList<WorldItem> Items => _items;

    // -------------------------------------------------------------------------
    // Spawning

    /// <summary>
    /// Evaluate spawn triggers, build a weighted loot table and place up to
    /// MaxItemsPerChunk items at walkable positions inside the chunk.
    /// Does nothing if the chunk has already had items spawned.
    /// </summary>
    public void SpawnItemsForChunk(Chunk chunk, GameContext context, SeededRNG rng)
    {
        if (chunk.SpawnedItems) return;
        chunk.SpawnedItems = true;

        // Collect candidate walkable positions
        var positions = chunk.Rooms.Count > 0
            ? chunk.WalkableRoomPositions()
            : chunk.WalkablePositions();

        if (positions.Count == 0) return;

        // Build base weight table from active triggers
        var weights = SpawnTriggerRegistry.BuildWeightTable(context);

        // Fall back to equal weights for all item types if no triggers fire
        if (weights.Count == 0)
        {
            foreach (ItemType t in Enum.GetValues<ItemType>())
                weights[t] = 1f;
        }

        // Determine spawn count (1 base for open-world, room-count for dungeons)
        int baseCount = chunk.Rooms.Count == 0 ? 1 : Math.Min(chunk.Rooms.Count, Constants.MaxItemsPerChunk);
        int spawnCount = Math.Min(baseCount, Constants.MaxItemsPerChunk);

        // Fisher-Yates shuffle with the provided seeded RNG
        var shuffled = new List<(int worldCol, int worldRow)>(positions);
        for (int i = shuffled.Count - 1; i >= 1; i--)
        {
            int j = (int)(rng.Next() % (ulong)(i + 1));
            (shuffled[i], shuffled[j]) = (shuffled[j], shuffled[i]);
        }

        for (int i = 0; i < Math.Min(spawnCount, shuffled.Count); i++)
        {
            var (wCol, wRow) = shuffled[i];
            var worldPos = new Vector2(wCol + 0.5f, wRow + 0.5f);

            var itemType = WeightedRandomItem(weights, rng);
            var item = CreateItem(itemType);
            _items.Add(new WorldItem(item, worldPos));
        }
    }

    // -------------------------------------------------------------------------
    // Per-frame update

    /// <summary>
    /// Advance hover animation on all items, attract items within AttractRange,
    /// collect items within PickupRange.
    /// </summary>
    public void Update(double deltaTime, Player player)
    {
        foreach (var item in _items)
        {
            if (item.IsCollected) continue;

            item.Update(deltaTime);

            float dist = IsometricMath.Distance(item.WorldPosition, player.WorldPosition);

            if (dist < Constants.ItemPickupRange)
            {
                item.ApplyEffect(player);
            }
            else if (dist < Constants.ItemAttractRange)
            {
                var dir = IsometricMath.Direction(item.WorldPosition, player.WorldPosition);
                float attractStep = Constants.ItemAttractSpeed * (float)deltaTime;
                item.WorldPosition += dir * attractStep;
            }
        }

        // Prune collected items
        _items.RemoveAll(i => i.IsCollected);
    }

    // -------------------------------------------------------------------------
    // Chunk unload cleanup

    /// <summary>
    /// Remove all items whose world position falls inside the given chunk.
    /// </summary>
    public void RemoveItemsInChunk(ChunkCoord coord)
    {
        var (ox, oy) = coord.WorldOrigin();
        float size = Constants.ChunkSize;
        _items.RemoveAll(item =>
            item.WorldPosition.X >= ox && item.WorldPosition.X < ox + size &&
            item.WorldPosition.Y >= oy && item.WorldPosition.Y < oy + size);
    }

    public void Clear() => _items.Clear();

    // -------------------------------------------------------------------------
    // Drawing

    public void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, Vector2 cameraPos)
    {
        foreach (var item in _items)
            item.Draw(spriteBatch, spriteManager, cameraPos);
    }

    // -------------------------------------------------------------------------
    // Helpers

    private static ItemType WeightedRandomItem(Dictionary<ItemType, float> weights, SeededRNG rng)
    {
        float total = 0f;
        foreach (var w in weights.Values) total += w;

        float roll = (float)(rng.Next() % 10000UL) / 10000f * total;
        foreach (var (type, weight) in weights)
        {
            roll -= weight;
            if (roll <= 0f) return type;
        }

        return ItemType.HealthPotion; // fallback
    }

    private static Item CreateItem(ItemType type)
    {
        return new Item(
            id:          type.ToString().ToLowerInvariant(),
            name:        ItemTypeName(type),
            description: string.Empty,
            type:        type,
            rarity:      Rarity.Common,
            value:       10,
            weight:      1f);
    }

    private static string ItemTypeName(ItemType type)
    {
        return type switch
        {
            ItemType.HealthPotion => "Health Potion",
            ItemType.ManaPotion   => "Mana Potion",
            ItemType.Antidote     => "Antidote",
            ItemType.Food         => "Food",
            ItemType.Sword        => "Sword",
            ItemType.Bow          => "Bow",
            ItemType.Staff        => "Staff",
            ItemType.Dagger       => "Dagger",
            ItemType.Axe          => "Axe",
            ItemType.Helmet       => "Helmet",
            ItemType.ChestArmor   => "Chest Armor",
            ItemType.Leggings     => "Leggings",
            ItemType.Boots        => "Boots",
            ItemType.Shield       => "Shield",
            ItemType.Gold         => "Gold",
            ItemType.Gem          => "Gem",
            ItemType.Artifact     => "Artifact",
            ItemType.QuestScroll  => "Quest Scroll",
            ItemType.AncientKey   => "Ancient Key",
            ItemType.CrystalShard => "Crystal Shard",
            ItemType.Wood         => "Wood",
            ItemType.Stone        => "Stone",
            ItemType.Iron         => "Iron",
            ItemType.Leather      => "Leather",
            ItemType.Cloth        => "Cloth",
            _                     => type.ToString()
        };
    }
}
