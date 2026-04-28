namespace IsometricRPG;

public enum StructureType
{
    // Natural
    TreeCluster,
    RockFormation,
    Ruins,
    // Buildings
    Cabin,
    Tower,
    Shrine,
    Camp,
    // Dungeon features
    DungeonEntrance,
    Vault,
    TreasureRoom,
    // Special
    Obelisk,
    Portal,
    Boss
}

public enum StructureCategory
{
    Natural,
    Building,
    Dungeon,
    Special
}

public class StructureTemplate
{
    public StructureType Type       { get; set; }
    public StructureCategory Category { get; set; }
    public (int Width, int Height) Size { get; set; }
    public TileType[,] Footprint    { get; set; }
    public int[,]? ElevationProfile  { get; set; }
    public float SpawnWeight         { get; set; }
    public List<Biome> AllowedBiomes { get; set; }
    public int MinElevation          { get; set; }
    public int MaxElevation          { get; set; }

    public StructureTemplate(
        StructureType type,
        StructureCategory category,
        (int Width, int Height) size,
        TileType[,] footprint,
        int[,]? elevationProfile,
        float spawnWeight,
        List<Biome> allowedBiomes,
        int minElevation = 0,
        int maxElevation = 100)
    {
        Type = type;
        Category = category;
        Size = size;
        Footprint = footprint;
        ElevationProfile = elevationProfile;
        SpawnWeight = spawnWeight;
        AllowedBiomes = allowedBiomes;
        MinElevation = minElevation;
        MaxElevation = maxElevation;
    }
}

public class Structure
{
    public StructureTemplate Template { get; set; }
    public int WorldX                 { get; set; }
    public int WorldY                 { get; set; }
    public bool IsDiscovered          { get; set; }
    public bool IsCleared             { get; set; }

    public Structure(StructureTemplate template, int worldX, int worldY)
    {
        Template = template;
        WorldX = worldX;
        WorldY = worldY;
        IsDiscovered = false;
        IsCleared = false;
    }

    public (int Width, int Height) Size => Template.Size;
    public StructureType Type => Template.Type;
    public StructureCategory Category => Template.Category;
}
