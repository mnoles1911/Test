namespace IsometricRPG;

public struct ChunkCoord : IEquatable<ChunkCoord>
{
    public int X { get; }
    public int Y { get; }

    public ChunkCoord(int x, int y)
    {
        X = x;
        Y = y;
    }

    /// <summary>
    /// Converts a world-space tile position to its containing chunk coordinate.
    /// </summary>
    public static ChunkCoord FromWorld(int tileX, int tileY)
    {
        return new ChunkCoord(
            (int)Math.Floor((double)tileX / Constants.ChunkSize),
            (int)Math.Floor((double)tileY / Constants.ChunkSize)
        );
    }

    /// <summary>
    /// Returns the world-space tile origin (top-left corner) of this chunk.
    /// </summary>
    public (int tileX, int tileY) WorldOrigin()
    {
        return (X * Constants.ChunkSize, Y * Constants.ChunkSize);
    }

    /// <summary>
    /// Manhattan distance to another chunk.
    /// </summary>
    public int ManhattanDistance(ChunkCoord other)
    {
        return Math.Abs(X - other.X) + Math.Abs(Y - other.Y);
    }

    // IEquatable<ChunkCoord>
    public bool Equals(ChunkCoord other) => X == other.X && Y == other.Y;
    public override bool Equals(object? obj) => obj is ChunkCoord c && Equals(c);
    public override int GetHashCode() => HashCode.Combine(X, Y);

    public static bool operator ==(ChunkCoord a, ChunkCoord b) => a.Equals(b);
    public static bool operator !=(ChunkCoord a, ChunkCoord b) => !a.Equals(b);

    public override string ToString() => $"ChunkCoord({X}, {Y})";
}
