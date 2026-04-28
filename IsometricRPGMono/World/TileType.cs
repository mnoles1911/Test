using Microsoft.Xna.Framework;

namespace IsometricRPG;

public enum Biome
{
    Ocean,
    Beach,
    Desert,
    Grassland,
    Forest,
    DenseForest,
    Swamp,
    Tundra,
    Snow,
    Mountain,
    HighMountain,
    Volcano
}

public static class BiomeExtensions
{
    public static Biome From(float elevation, float moisture)
    {
        if (elevation < 0.1f) return Biome.Ocean;
        if (elevation < 0.15f) return Biome.Beach;

        if (elevation < 0.4f)
        {
            if (moisture < 0.2f) return Biome.Desert;
            if (moisture < 0.5f) return Biome.Grassland;
            if (moisture < 0.8f) return Biome.Forest;
            return Biome.Swamp;
        }

        if (elevation < 0.65f)
        {
            if (moisture < 0.25f) return Biome.Desert;
            if (moisture < 0.55f) return Biome.Grassland;
            if (moisture < 0.85f) return Biome.Forest;
            return Biome.DenseForest;
        }

        if (elevation < 0.8f)
        {
            if (moisture < 0.3f) return Biome.Tundra;
            return Biome.Mountain;
        }

        if (elevation < 0.9f)
        {
            if (moisture < 0.2f) return Biome.Volcano;
            return Biome.HighMountain;
        }

        return Biome.Snow;
    }
}

public enum TileType
{
    // Terrain
    Grass,
    DarkGrass,
    Sand,
    Water,
    ShallowWater,
    DeepWater,
    Stone,
    DarkStone,
    Snow,
    Ice,
    Dirt,
    Mud,
    Lava,
    // Structures
    Wall,
    Floor,
    Door,
    Chest,
    Altar,
    Pillar,
    // Vegetation
    Tree,
    DenseTree,
    Bush,
    Cactus,
    // Special
    Void,
    Cliff,
    Bridge
}

public static class TileTypeExtensions
{
    public static bool IsWalkable(this TileType tile)
    {
        return tile switch
        {
            TileType.Grass       => true,
            TileType.DarkGrass   => true,
            TileType.Sand        => true,
            TileType.Stone       => true,
            TileType.DarkStone   => true,
            TileType.Snow        => true,
            TileType.Dirt        => true,
            TileType.Floor       => true,
            TileType.Door        => true,
            TileType.Bridge      => true,
            _                    => false
        };
    }

    public static Color TileColor(this TileType tile)
    {
        return tile switch
        {
            TileType.Grass       => new Color(51,  153, 51),
            TileType.DarkGrass   => new Color(34,  102, 34),
            TileType.Sand        => new Color(194, 178, 128),
            TileType.Water       => new Color(64,  164, 223),
            TileType.ShallowWater=> new Color(100, 180, 230),
            TileType.DeepWater   => new Color(30,  100, 180),
            TileType.Stone       => new Color(128, 128, 128),
            TileType.DarkStone   => new Color(80,  80,  80),
            TileType.Snow        => new Color(240, 240, 255),
            TileType.Ice         => new Color(200, 225, 255),
            TileType.Dirt        => new Color(139, 90,  43),
            TileType.Mud         => new Color(100, 70,  30),
            TileType.Lava        => new Color(207, 16,  32),
            TileType.Wall        => new Color(90,  90,  90),
            TileType.Floor       => new Color(160, 140, 100),
            TileType.Door        => new Color(139, 69,  19),
            TileType.Chest       => new Color(184, 134, 11),
            TileType.Altar       => new Color(148, 0,   211),
            TileType.Pillar      => new Color(105, 105, 105),
            TileType.Tree        => new Color(0,   100, 0),
            TileType.DenseTree   => new Color(0,   70,  0),
            TileType.Bush        => new Color(60,  120, 60),
            TileType.Cactus      => new Color(50,  130, 50),
            TileType.Void        => new Color(0,   0,   0),
            TileType.Cliff       => new Color(100, 85,  70),
            TileType.Bridge      => new Color(160, 120, 80),
            _                    => new Color(128, 128, 128)
        };
    }
}
