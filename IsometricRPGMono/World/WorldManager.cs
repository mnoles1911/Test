using Microsoft.Xna.Framework;

namespace IsometricRPG;

public class WorldManager
{
    private readonly Dictionary<ChunkCoord, Chunk> _chunks = new();
    private readonly PerlinNoise _elevNoise;
    private readonly PerlinNoise _moistureNoise;
    private ChunkCoord _lastPlayerChunk;
    private bool _firstUpdate = true;

    public IReadOnlyDictionary<ChunkCoord, Chunk> LoadedChunks => _chunks;

    public WorldManager()
    {
        _elevNoise    = new PerlinNoise(Constants.WorldSeed);
        _moistureNoise = new PerlinNoise(Constants.WorldSeed + 12345);
    }

    /// Call every frame. Returns (loaded, unloaded) coord lists.
    public (List<ChunkCoord> loaded, List<ChunkCoord> unloaded) UpdateAroundPlayer(Vector2 worldPos)
    {
        int tileX = (int)MathF.Floor(worldPos.X);
        int tileY = (int)MathF.Floor(worldPos.Y);
        var playerChunk = ChunkCoord.FromWorld(tileX, tileY);

        if (!_firstUpdate && playerChunk == _lastPlayerChunk)
            return (new List<ChunkCoord>(), new List<ChunkCoord>());

        _firstUpdate = false;
        _lastPlayerChunk = playerChunk;

        var loaded   = new List<ChunkCoord>();
        var unloaded = new List<ChunkCoord>();

        int r = Constants.LoadRadius;
        for (int dy = -r; dy <= r; dy++)
            for (int dx = -r; dx <= r; dx++)
            {
                var coord = new ChunkCoord(playerChunk.X + dx, playerChunk.Y + dy);
                if (!_chunks.ContainsKey(coord))
                {
                    _chunks[coord] = new Chunk(coord, _elevNoise, _moistureNoise);
                    loaded.Add(coord);
                }
            }

        var toUnload = _chunks.Keys
            .Where(c => c.ChebyshevDistance(playerChunk) > Constants.UnloadRadius)
            .ToList();
        foreach (var c in toUnload)
        {
            _chunks.Remove(c);
            unloaded.Add(c);
        }

        return (loaded, unloaded);
    }

    public void InitialLoad(Vector2 worldPos) => UpdateAroundPlayer(worldPos);

    // ---- Tile queries ----

    public TileType? TileAt(int worldCol, int worldRow)
    {
        var coord = ChunkCoord.FromWorld(worldCol, worldRow);
        if (!_chunks.TryGetValue(coord, out var chunk)) return null;
        var (ox, oy) = coord.WorldOrigin();
        return chunk.TileAt(worldCol - ox, worldRow - oy);
    }

    public float? ElevationAt(int worldCol, int worldRow)
    {
        var coord = ChunkCoord.FromWorld(worldCol, worldRow);
        if (!_chunks.TryGetValue(coord, out var chunk)) return null;
        var (ox, oy) = coord.WorldOrigin();
        return chunk.ElevationAt(worldCol - ox, worldRow - oy);
    }

    public bool IsWalkable(Vector2 worldPos)
    {
        int col = (int)MathF.Floor(worldPos.X + 0.5f);
        int row = (int)MathF.Floor(worldPos.Y + 0.5f);
        return TileAt(col, row)?.IsWalkable() ?? false;
    }

    public bool IsWalkable(Vector2 from, Vector2 to)
    {
        if (!IsWalkable(to)) return false;
        int fc = (int)MathF.Floor(from.X + 0.5f); int fr = (int)MathF.Floor(from.Y + 0.5f);
        int tc = (int)MathF.Floor(to.X   + 0.5f); int tr = (int)MathF.Floor(to.Y   + 0.5f);
        float? fe = ElevationAt(fc, fr);
        float? te = ElevationAt(tc, tr);
        if (fe == null || te == null) return false;
        // Elevation is [0,1]; multiply by 100 to compare against integer-percent threshold.
        return MathF.Abs(te.Value - fe.Value) * 100f <= Constants.MaxWalkableElevationDiff;
    }

    public Biome? BiomeAt(Vector2 worldPos)
    {
        var coord = ChunkCoord.FromWorld((int)MathF.Floor(worldPos.X), (int)MathF.Floor(worldPos.Y));
        return _chunks.TryGetValue(coord, out var c) ? c.Biome : null;
    }

    public Chunk? ChunkAt(Vector2 worldPos)
    {
        var coord = ChunkCoord.FromWorld((int)MathF.Floor(worldPos.X), (int)MathF.Floor(worldPos.Y));
        return _chunks.TryGetValue(coord, out var c) ? c : null;
    }

    public bool IsPositionLoaded(int worldCol, int worldRow)
        => _chunks.ContainsKey(ChunkCoord.FromWorld(worldCol, worldRow));

    public List<Chunk> ChunksNeedingItemSpawn()  => _chunks.Values.Where(c => !c.SpawnedItems).ToList();
    public List<Chunk> ChunksNeedingEnemySpawn() => _chunks.Values.Where(c => !c.SpawnedEnemies).ToList();
}
