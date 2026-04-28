using Microsoft.Xna.Framework;

namespace IsometricRPG;

public static class IsometricMath
{
    public static Vector2 GridToScreen(int col, int row, int elevation = 0)
    {
        float x = (float)(col - row) * (Constants.TileWidth / 2f);
        float baseY = (float)(col + row) * (Constants.TileHeight / 2f);
        float heightOffset = (float)elevation * Constants.ElevationHeightMultiplier;
        float y = baseY - heightOffset;
        // MonoGame is Y-down: no negation of y
        return new Vector2(x, y);
    }

    public static Vector2 WorldToScreen(Vector2 point)
    {
        float x = (point.X - point.Y) * (Constants.TileWidth / 2f);
        float y = (point.X + point.Y) * (Constants.TileHeight / 2f);
        // MonoGame is Y-down: no negation of y
        return new Vector2(x, y);
    }

    public static Vector2 ScreenToWorld(Vector2 point)
    {
        // MonoGame Y-down: use point.Y directly (no negation)
        float x = (point.X / (Constants.TileWidth / 2f) + point.Y / (Constants.TileHeight / 2f)) / 2f;
        float y = (point.Y / (Constants.TileHeight / 2f) - point.X / (Constants.TileWidth / 2f)) / 2f;
        return new Vector2(x, y);
    }

    public static float Distance(Vector2 a, Vector2 b)
    {
        float dx = b.X - a.X;
        float dy = b.Y - a.Y;
        return MathF.Sqrt(dx * dx + dy * dy);
    }

    public static Vector2 Direction(Vector2 from, Vector2 to)
    {
        float dx = to.X - from.X;
        float dy = to.Y - from.Y;
        float len = MathF.Sqrt(dx * dx + dy * dy);
        if (len < 1e-6f) return Vector2.Zero;
        return new Vector2(dx / len, dy / len);
    }
}
