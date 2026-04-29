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
            TileType.Grass       => new Color(72,  95,  45),
            TileType.DarkGrass   => new Color(50,  70,  30),
            TileType.Sand        => new Color(185, 155, 95),
            TileType.Water       => new Color(45,  110, 160),
            TileType.ShallowWater=> new Color(70,  140, 180),
            TileType.DeepWater   => new Color(25,  70,  120),
            TileType.Stone       => new Color(105, 95,  85),
            TileType.DarkStone   => new Color(65,  58,  52),
            TileType.Snow        => new Color(220, 225, 230),
            TileType.Ice         => new Color(185, 210, 235),
            TileType.Dirt        => new Color(120, 78,  38),
            TileType.Mud         => new Color(80,  58,  28),
            TileType.Lava        => new Color(190, 55,  15),
            TileType.Wall        => new Color(75,  68,  58),
            TileType.Floor       => new Color(140, 118, 82),
            TileType.Door        => new Color(100, 55,  20),
            TileType.Chest       => new Color(160, 110, 20),
            TileType.Altar       => new Color(100, 25,  140),
            TileType.Pillar      => new Color(90,  82,  72),
            TileType.Tree        => new Color(35,  80,  35),
            TileType.DenseTree   => new Color(25,  58,  25),
            TileType.Bush        => new Color(55,  90,  45),
            TileType.Cactus      => new Color(45,  100, 45),
            TileType.Void        => new Color(5,   5,   5),
            TileType.Cliff       => new Color(85,  72,  58),
            TileType.Bridge      => new Color(130, 95,  55),
            _                    => new Color(128, 128, 128)
        };
    }
}
