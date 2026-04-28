using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace IsometricRPG;

public class WorldRenderer
{
    private readonly PrimitiveRenderer _prim;

    public WorldRenderer(PrimitiveRenderer prim)
    {
        _prim = prim;
    }

    /// Draw all loaded chunks. Must be called BEFORE SpriteBatch.Begin().
    /// cameraPos is the screen-space centre the camera is looking at.
    public void Draw(WorldManager world, Vector2 cameraPos)
    {
        _prim.Begin(cameraPos);

        foreach (var (coord, chunk) in world.LoadedChunks)
        {
            DrawChunk(chunk);
        }
    }

    private void DrawChunk(Chunk chunk)
    {
        int size = Constants.ChunkSize;
        var (ox, oy) = chunk.Coord.WorldOrigin();

        for (int row = 0; row < size; row++)
            for (int col = 0; col < size; col++)
            {
                var tile = chunk.Tiles[row, col];
                float elevNorm = chunk.Elevation[row, col];
                // Convert normalised elevation [0,1] → integer steps for height offset
                int elevInt = (int)(elevNorm * 100f);

                var screenPos = IsometricMath.GridToScreen(ox + col, oy + row, elevInt);
                var baseColor = tile.TileColor();

                _prim.DrawDiamond(screenPos, baseColor, DarkenColor(baseColor, 0.7f));

                // Cliff face if significant drop to the right
                if (col + 1 < size)
                {
                    int neighborElev = (int)(chunk.Elevation[row, col + 1] * 100f);
                    if (elevInt - neighborElev >= Constants.CliffThreshold)
                        DrawCliffRight(screenPos, elevInt - neighborElev, baseColor);
                }
                // Cliff face if significant drop below
                if (row + 1 < size)
                {
                    int neighborElev = (int)(chunk.Elevation[row + 1, col] * 100f);
                    if (elevInt - neighborElev >= Constants.CliffThreshold)
                        DrawCliffBottom(screenPos, elevInt - neighborElev, baseColor);
                }
            }
    }

    private void DrawCliffRight(Vector2 tileCenter, int heightDiff, Color tileColor)
    {
        float hw = Constants.TileWidth  / 2f;
        float hh = Constants.TileHeight / 2f;
        float vh = heightDiff * Constants.ElevationHeightMultiplier;
        var cliff = DarkenColor(tileColor, 0.6f);
        // Right edge quad
        _prim.DrawQuad(
            new Vector2(tileCenter.X + hw, tileCenter.Y),
            new Vector2(tileCenter.X,      tileCenter.Y + hh),
            new Vector2(tileCenter.X,      tileCenter.Y + hh + vh),
            new Vector2(tileCenter.X + hw, tileCenter.Y + vh),
            cliff);
    }

    private void DrawCliffBottom(Vector2 tileCenter, int heightDiff, Color tileColor)
    {
        float hw = Constants.TileWidth  / 2f;
        float hh = Constants.TileHeight / 2f;
        float vh = heightDiff * Constants.ElevationHeightMultiplier;
        var cliff = DarkenColor(tileColor, 0.65f);
        // Bottom edge quad
        _prim.DrawQuad(
            new Vector2(tileCenter.X,      tileCenter.Y + hh),
            new Vector2(tileCenter.X - hw, tileCenter.Y),
            new Vector2(tileCenter.X - hw, tileCenter.Y + vh),
            new Vector2(tileCenter.X,      tileCenter.Y + hh + vh),
            cliff);
    }

    private static Color DarkenColor(Color c, float factor)
        => new Color((int)(c.R * factor), (int)(c.G * factor), (int)(c.B * factor), c.A);
}
