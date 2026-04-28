using Microsoft.Xna.Framework;

namespace IsometricRPG;

public sealed class Chunk
{
    public ChunkCoord Coord     { get; }
    public Biome      Biome     { get; }
    public TileType[,] Tiles    { get; }          // [row, col]
    public float[,]   Elevation { get; }          // [row, col], normalised 0–1
    public List<Room>      Rooms      { get; }
    public List<Structure> Structures { get; }
    public bool SpawnedEnemies { get; set; }
    public bool SpawnedItems   { get; set; }

    private const int Size = Constants.ChunkSize;

    public Chunk(ChunkCoord coord, PerlinNoise elevNoise, PerlinNoise moistureNoise)
    {
        Coord     = coord;
        Tiles     = new TileType[Size, Size];
        Elevation = new float[Size, Size];

        var (ox, oy) = coord.WorldOrigin();

        // 1. Sample biome from chunk centre
        float cx = (ox + Size / 2f) * 0.02f;
        float cy = (oy + Size / 2f) * 0.02f;
        float elevSample     = Normalise(elevNoise.Fractal(cx, cy, octaves: 3));
        float moistureSample = Normalise(moistureNoise.Fractal(cx, cy, octaves: 3));
        Biome = BiomeExtensions.From(elevSample, moistureSample);

        // 2. Fill elevation grid
        for (int row = 0; row < Size; row++)
            for (int col = 0; col < Size; col++)
            {
                float nx = (ox + col) * 0.03f;
                float ny = (oy + row) * 0.03f;
                Elevation[row, col] = Normalise(elevNoise.Fractal(nx, ny, octaves: 5));
            }

        var rng = new SeededRNG(ChunkSeed(coord));

        // 3. Dungeon chunks: carve rooms
        if (Biome == Biome.Forest || Biome == Biome.Grassland || rng.NextFloat() < 0.15f)
        {
            // Only generate dungeon rooms for dungeon-eligible biomes or random 15% chance
        }

        bool hasDungeon = Biome == Biome.Mountain || Biome == Biome.HighMountain || rng.NextFloat() < 0.1f;
        if (hasDungeon)
        {
            rng = new SeededRNG(ChunkSeed(coord)); // reset for determinism
            Rooms = DungeonGenerator.Generate(Tiles, Size, rng);
        }
        else
        {
            Rooms = new List<Room>();
            // Fill tiles with open-world terrain
            FillTerrain(elevNoise, moistureNoise, ox, oy);
        }

        // 4. Structures (non-dungeon)
        if (!hasDungeon)
        {
            Structures = StructureGenerator.GenerateForChunk(ox, oy, Elevation, Biome, rng);
            ApplyStructures();
        }
        else
        {
            Structures = new List<Structure>();
        }
    }

    // -------------------------------------------------------------------------

    private void FillTerrain(PerlinNoise elevNoise, PerlinNoise moistureNoise, int ox, int oy)
    {
        var rng = new SeededRNG(ChunkSeed(Coord) ^ 0xABCDEF12);
        for (int row = 0; row < Size; row++)
            for (int col = 0; col < Size; col++)
            {
                float nx = (ox + col) * 0.08f;
                float ny = (oy + row) * 0.08f;
                float n = elevNoise.Fractal(nx, ny, octaves: 4);
                float m = moistureNoise.Fractal(nx * 0.5f, ny * 0.5f, octaves: 3);
                Tiles[row, col] = TileForBiome(n, m, rng);
            }
    }

    private TileType TileForBiome(float n, float m, SeededRNG rng)
    {
        return Biome switch
        {
            Biome.Forest or Biome.DenseForest => n < -0.35f ? TileType.Water :
                                                 n < -0.15f ? TileType.Dirt  :
                                                 rng.NextFloat() < 0.05f ? TileType.Stone : TileType.Grass,
            Biome.Desert  => n < -0.4f ? TileType.Water :
                             n > 0.3f  ? TileType.Stone :
                             rng.NextFloat() < 0.08f ? TileType.Dirt : TileType.Sand,
            Biome.Swamp   => n < -0.1f ? TileType.Water :
                             n < 0.1f  ? TileType.Mud   :
                             rng.NextFloat() < 0.1f ? TileType.Dirt : TileType.Grass,
            Biome.Snow or Biome.Tundra => n < -0.3f ? TileType.Water :
                                          n > 0.35f  ? TileType.Stone :
                                          rng.NextFloat() < 0.06f ? TileType.Dirt : TileType.Snow,
            Biome.Mountain or Biome.HighMountain => n < -0.2f ? TileType.Water :
                                                    n > 0.5f  ? TileType.DarkStone : TileType.Stone,
            Biome.Ocean or Biome.Beach => n < 0.0f ? TileType.DeepWater :
                                          n < 0.15f ? TileType.ShallowWater : TileType.Sand,
            Biome.Grassland => n < -0.3f ? TileType.Water :
                                rng.NextFloat() < 0.04f ? TileType.Dirt : TileType.Grass,
            _               => TileType.Grass,
        };
    }

    private void ApplyStructures()
    {
        var (ox, oy) = Coord.WorldOrigin();
        foreach (var s in Structures)
        {
            int localX = s.WorldX - ox;
            int localY = s.WorldY - oy;
            for (int row = 0; row < s.Template.Size.Height; row++)
                for (int col = 0; col < s.Template.Size.Width; col++)
                {
                    int tr = localY + row;
                    int tc = localX + col;
                    if (tr >= 0 && tr < Size && tc >= 0 && tc < Size)
                        Tiles[tr, tc] = s.Template.Footprint[row, col];
                }
        }
    }

    // -------------------------------------------------------------------------
    // Queries

    public TileType? TileAt(int localCol, int localRow)
    {
        if (localCol < 0 || localCol >= Size || localRow < 0 || localRow >= Size) return null;
        return Tiles[localRow, localCol];
    }

    public float? ElevationAt(int localCol, int localRow)
    {
        if (localCol < 0 || localCol >= Size || localRow < 0 || localRow >= Size) return null;
        return Elevation[localRow, localCol];
    }

    public List<(int worldCol, int worldRow)> WalkablePositions()
    {
        var (ox, oy) = Coord.WorldOrigin();
        var result = new List<(int, int)>();
        for (int row = 0; row < Size; row++)
            for (int col = 0; col < Size; col++)
                if (Tiles[row, col].IsWalkable())
                    result.Add((ox + col, oy + row));
        return result;
    }

    public List<(int worldCol, int worldRow)> WalkableRoomPositions()
    {
        var (ox, oy) = Coord.WorldOrigin();
        var result = new List<(int, int)>();
        foreach (var room in Rooms)
            for (int row = room.Y + 1; row < room.Y + room.Height - 1; row++)
                for (int col = room.X + 1; col < room.X + room.Width - 1; col++)
                    if (row >= 0 && row < Size && col >= 0 && col < Size && Tiles[row, col].IsWalkable())
                        result.Add((ox + col, oy + row));
        return result;
    }

    // -------------------------------------------------------------------------
    // Helpers

    private static float Normalise(float v) => (v + 1f) / 2f;  // [-1,1] → [0,1]

    private static ulong ChunkSeed(ChunkCoord c)
    {
        ulong seed = Constants.WorldSeed;
        unchecked
        {
            seed ^= (ulong)(long)c.X * 0x517CC1B727220A95UL;
            seed ^= (ulong)(long)c.Y * 0x6C62272E07BB0142UL;
            seed ^= seed >> 33;
            seed *= 0xFF51AFD7ED558CCDUL;
            seed ^= seed >> 33;
        }
        return seed;
    }
}
