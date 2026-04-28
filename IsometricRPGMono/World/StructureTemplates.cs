namespace IsometricRPG;

/// <summary>
/// Catalogue of all pre-defined structure templates (15 total).
/// </summary>
public static class StructureTemplates
{
    // -------------------------------------------------------------------------
    // Helper aliases
    // -------------------------------------------------------------------------
    private static TileType W  => TileType.Wall;
    private static TileType F  => TileType.Floor;
    private static TileType D  => TileType.Door;
    private static TileType T  => TileType.Tree;
    private static TileType DT => TileType.DenseTree;
    private static TileType B  => TileType.Bush;
    private static TileType S  => TileType.Stone;
    private static TileType C  => TileType.Chest;
    private static TileType A  => TileType.Altar;
    private static TileType P  => TileType.Pillar;
    private static TileType Gr => TileType.Grass;
    private static TileType Di => TileType.Dirt;
    private static TileType Cl => TileType.Cliff;
    private static TileType Ca => TileType.Cactus;
    private static TileType V  => TileType.Void;

    // -------------------------------------------------------------------------
    // 1. Tree Cluster (5×5)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate TreeCluster = new StructureTemplate(
        type:     StructureType.TreeCluster,
        category: StructureCategory.Natural,
        size:     (5, 5),
        footprint: new TileType[5, 5]
        {
            { Gr, T,  T,  Gr, Gr },
            { T,  DT, DT, T,  Gr },
            { T,  DT, DT, DT, T  },
            { Gr, T,  DT, T,  Gr },
            { Gr, Gr, T,  Gr, Gr }
        },
        elevationProfile: null,
        spawnWeight: 3.0f,
        allowedBiomes: new List<Biome>
        {
            Biome.Grassland, Biome.Forest, Biome.DenseForest
        });

    // -------------------------------------------------------------------------
    // 2. Rock Formation (4×4)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate RockFormation = new StructureTemplate(
        type:     StructureType.RockFormation,
        category: StructureCategory.Natural,
        size:     (4, 4),
        footprint: new TileType[4, 4]
        {
            { Gr, S,  S,  Gr },
            { S,  Cl, Cl, S  },
            { S,  Cl, S,  Gr },
            { Gr, S,  Gr, Gr }
        },
        elevationProfile: new int[4, 4]
        {
            { 0, 1, 1, 0 },
            { 1, 2, 2, 1 },
            { 1, 2, 1, 0 },
            { 0, 1, 0, 0 }
        },
        spawnWeight: 2.0f,
        allowedBiomes: new List<Biome>
        {
            Biome.Mountain, Biome.HighMountain, Biome.Tundra, Biome.Desert
        });

    // -------------------------------------------------------------------------
    // 3. Ruins (6×6)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate Ruins = new StructureTemplate(
        type:     StructureType.Ruins,
        category: StructureCategory.Natural,
        size:     (6, 6),
        footprint: new TileType[6, 6]
        {
            { W,  W,  Gr, Gr, W,  W  },
            { W,  F,  F,  F,  F,  W  },
            { Gr, F,  A,  F,  F,  Gr },
            { Gr, F,  F,  C,  F,  Gr },
            { W,  F,  F,  F,  F,  W  },
            { W,  W,  Gr, Gr, W,  W  }
        },
        elevationProfile: null,
        spawnWeight: 1.5f,
        allowedBiomes: new List<Biome>
        {
            Biome.Grassland, Biome.Forest, Biome.Desert, Biome.Tundra
        });

    // -------------------------------------------------------------------------
    // 4. Cabin (5×5)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate Cabin = new StructureTemplate(
        type:     StructureType.Cabin,
        category: StructureCategory.Building,
        size:     (5, 5),
        footprint: new TileType[5, 5]
        {
            { W,  W,  W,  W,  W  },
            { W,  F,  F,  F,  W  },
            { W,  F,  F,  F,  W  },
            { W,  F,  F,  F,  W  },
            { W,  W,  D,  W,  W  }
        },
        elevationProfile: null,
        spawnWeight: 1.0f,
        allowedBiomes: new List<Biome>
        {
            Biome.Grassland, Biome.Forest, Biome.Tundra
        });

    // -------------------------------------------------------------------------
    // 5. Tower (4×4)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate Tower = new StructureTemplate(
        type:     StructureType.Tower,
        category: StructureCategory.Building,
        size:     (4, 4),
        footprint: new TileType[4, 4]
        {
            { W,  W,  W,  W  },
            { W,  F,  F,  W  },
            { W,  F,  F,  W  },
            { W,  D,  W,  W  }
        },
        elevationProfile: new int[4, 4]
        {
            { 2, 2, 2, 2 },
            { 2, 3, 3, 2 },
            { 2, 3, 3, 2 },
            { 2, 1, 2, 2 }
        },
        spawnWeight: 0.8f,
        allowedBiomes: new List<Biome>
        {
            Biome.Grassland, Biome.Mountain, Biome.Desert
        });

    // -------------------------------------------------------------------------
    // 6. Shrine (3×3)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate Shrine = new StructureTemplate(
        type:     StructureType.Shrine,
        category: StructureCategory.Building,
        size:     (3, 3),
        footprint: new TileType[3, 3]
        {
            { P,  W,  P  },
            { Gr, A,  Gr },
            { Gr, Di, Gr }
        },
        elevationProfile: null,
        spawnWeight: 1.2f,
        allowedBiomes: new List<Biome>
        {
            Biome.Grassland, Biome.Forest, Biome.Mountain, Biome.Beach
        });

    // -------------------------------------------------------------------------
    // 7. Camp (5×5)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate Camp = new StructureTemplate(
        type:     StructureType.Camp,
        category: StructureCategory.Building,
        size:     (5, 5),
        footprint: new TileType[5, 5]
        {
            { Gr, T,  Gr, T,  Gr },
            { T,  Di, Di, Di, T  },
            { Gr, Di, A,  Di, Gr },
            { T,  Di, Di, Di, T  },
            { Gr, T,  Gr, T,  Gr }
        },
        elevationProfile: null,
        spawnWeight: 1.5f,
        allowedBiomes: new List<Biome>
        {
            Biome.Grassland, Biome.Forest, Biome.Desert, Biome.Tundra
        });

    // -------------------------------------------------------------------------
    // 8. Dungeon Entrance (6×6)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate DungeonEntrance = new StructureTemplate(
        type:     StructureType.DungeonEntrance,
        category: StructureCategory.Dungeon,
        size:     (6, 6),
        footprint: new TileType[6, 6]
        {
            { W,  W,  W,  W,  W,  W  },
            { W,  S,  S,  S,  S,  W  },
            { W,  S,  F,  F,  S,  W  },
            { W,  S,  F,  F,  S,  W  },
            { W,  S,  S,  S,  S,  W  },
            { W,  W,  D,  D,  W,  W  }
        },
        elevationProfile: null,
        spawnWeight: 0.5f,
        allowedBiomes: new List<Biome>
        {
            Biome.Grassland, Biome.Forest, Biome.Mountain, Biome.Desert,
            Biome.Tundra, Biome.DenseForest
        },
        minElevation: 10);

    // -------------------------------------------------------------------------
    // 9. Vault (5×5)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate Vault = new StructureTemplate(
        type:     StructureType.Vault,
        category: StructureCategory.Dungeon,
        size:     (5, 5),
        footprint: new TileType[5, 5]
        {
            { W,  W,  W,  W,  W  },
            { W,  C,  F,  C,  W  },
            { W,  F,  A,  F,  W  },
            { W,  C,  F,  C,  W  },
            { W,  W,  D,  W,  W  }
        },
        elevationProfile: null,
        spawnWeight: 0.3f,
        allowedBiomes: new List<Biome>
        {
            Biome.Grassland, Biome.Mountain, Biome.HighMountain
        },
        minElevation: 20);

    // -------------------------------------------------------------------------
    // 10. Treasure Room (4×4)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate TreasureRoom = new StructureTemplate(
        type:     StructureType.TreasureRoom,
        category: StructureCategory.Dungeon,
        size:     (4, 4),
        footprint: new TileType[4, 4]
        {
            { W,  W,  W,  W  },
            { W,  C,  C,  W  },
            { W,  C,  C,  W  },
            { W,  W,  D,  W  }
        },
        elevationProfile: null,
        spawnWeight: 0.4f,
        allowedBiomes: new List<Biome>
        {
            Biome.Grassland, Biome.Forest, Biome.Mountain,
            Biome.Desert, Biome.DenseForest, Biome.Tundra
        });

    // -------------------------------------------------------------------------
    // 11. Obelisk (3×3)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate Obelisk = new StructureTemplate(
        type:     StructureType.Obelisk,
        category: StructureCategory.Special,
        size:     (3, 3),
        footprint: new TileType[3, 3]
        {
            { Gr, P,  Gr },
            { Gr, A,  Gr },
            { Di, Di, Di }
        },
        elevationProfile: new int[3, 3]
        {
            { 0, 2, 0 },
            { 0, 1, 0 },
            { 0, 0, 0 }
        },
        spawnWeight: 0.6f,
        allowedBiomes: new List<Biome>
        {
            Biome.Desert, Biome.Tundra, Biome.Grassland, Biome.Mountain
        });

    // -------------------------------------------------------------------------
    // 12. Portal (4×4)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate Portal = new StructureTemplate(
        type:     StructureType.Portal,
        category: StructureCategory.Special,
        size:     (4, 4),
        footprint: new TileType[4, 4]
        {
            { Gr, P,  P,  Gr },
            { P,  A,  A,  P  },
            { P,  A,  A,  P  },
            { Gr, P,  P,  Gr }
        },
        elevationProfile: null,
        spawnWeight: 0.2f,
        allowedBiomes: new List<Biome>
        {
            Biome.Grassland, Biome.Forest, Biome.Mountain,
            Biome.HighMountain, Biome.Desert
        });

    // -------------------------------------------------------------------------
    // 13. Boss Arena (8×8)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate Boss = new StructureTemplate(
        type:     StructureType.Boss,
        category: StructureCategory.Special,
        size:     (8, 8),
        footprint: new TileType[8, 8]
        {
            { W,  W,  W,  W,  W,  W,  W,  W  },
            { W,  P,  F,  F,  F,  F,  P,  W  },
            { W,  F,  F,  F,  F,  F,  F,  W  },
            { W,  F,  F,  A,  A,  F,  F,  W  },
            { W,  F,  F,  A,  A,  F,  F,  W  },
            { W,  F,  F,  F,  F,  F,  F,  W  },
            { W,  P,  F,  F,  F,  F,  P,  W  },
            { W,  W,  W,  D,  D,  W,  W,  W  }
        },
        elevationProfile: null,
        spawnWeight: 0.1f,
        allowedBiomes: new List<Biome>
        {
            Biome.Mountain, Biome.HighMountain, Biome.Volcano
        },
        minElevation: 30);

    // -------------------------------------------------------------------------
    // 14. Swamp Hut (4×4)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate SwampHut = new StructureTemplate(
        type:     StructureType.Cabin,
        category: StructureCategory.Building,
        size:     (4, 4),
        footprint: new TileType[4, 4]
        {
            { W,  W,  W,  W  },
            { W,  F,  F,  W  },
            { W,  F,  C,  W  },
            { W,  D,  W,  W  }
        },
        elevationProfile: null,
        spawnWeight: 1.0f,
        allowedBiomes: new List<Biome>
        {
            Biome.Swamp
        });

    // -------------------------------------------------------------------------
    // 15. Desert Outpost (5×5)
    // -------------------------------------------------------------------------
    public static readonly StructureTemplate DesertOutpost = new StructureTemplate(
        type:     StructureType.Camp,
        category: StructureCategory.Building,
        size:     (5, 5),
        footprint: new TileType[5, 5]
        {
            { Ca, Gr, W,  Gr, Ca },
            { Gr, W,  W,  W,  Gr },
            { W,  W,  F,  W,  W  },
            { Gr, W,  D,  W,  Gr },
            { Ca, Gr, Gr, Gr, Ca }
        },
        elevationProfile: null,
        spawnWeight: 1.2f,
        allowedBiomes: new List<Biome>
        {
            Biome.Desert
        });

    // -------------------------------------------------------------------------
    // Master list
    // -------------------------------------------------------------------------
    public static readonly List<StructureTemplate> All = new List<StructureTemplate>
    {
        TreeCluster,
        RockFormation,
        Ruins,
        Cabin,
        Tower,
        Shrine,
        Camp,
        DungeonEntrance,
        Vault,
        TreasureRoom,
        Obelisk,
        Portal,
        Boss,
        SwampHut,
        DesertOutpost
    };
}
