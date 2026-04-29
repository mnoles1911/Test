using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace IsometricRPG;

/// <summary>
/// 120×120 minimap rendered in the top-right corner.
/// Iterates loaded chunks, draws 2×2 pixel dots per tile, player as a 4×4 white dot at center.
/// </summary>
public class Minimap
{
    private const int MapSize      = 120;
    private const int DotSize      = 2;
    private const int PlayerDotSize = 4;

    // Top-right corner position: 1280 - 130, 10
    private const int MapX = 1280 - 130;
    private const int MapY = 10;

    // Scale: pixels per world tile on minimap
    private const float PixelsPerTile = 2f;

    public void Draw(
        SpriteBatch   spriteBatch,
        SpriteManager spriteManager,
        WorldManager  worldManager,
        Vector2       playerWorldPos,
        Vector2       cameraPos)
    {
        // Background panel
        var bgRect = new Rectangle(MapX - 2, MapY - 2, MapSize + 4, MapSize + 4);
        spriteBatch.Draw(spriteManager.GetPixel(UITheme.Panel), bgRect, Color.White);

        // Border
        DrawBorder(spriteBatch, spriteManager, bgRect, UITheme.PanelBorder, 2);

        // Clip to minimap bounds — draw tiles relative to player (player at center)
        var mapCenter = new Vector2(MapX + MapSize / 2f, MapY + MapSize / 2f);

        // Iterate all loaded chunks
        foreach (var (coord, chunk) in worldManager.LoadedChunks)
        {
            var (ox, oy) = coord.WorldOrigin();

            for (int row = 0; row < Constants.ChunkSize; row++)
            {
                for (int col = 0; col < Constants.ChunkSize; col++)
                {
                    float worldCol = ox + col + 0.5f;
                    float worldRow = oy + row + 0.5f;

                    // Position relative to player, scaled to minimap pixels
                    float relX = (worldCol - playerWorldPos.X) * PixelsPerTile;
                    float relY = (worldRow - playerWorldPos.Y) * PixelsPerTile;

                    float dotX = mapCenter.X + relX - DotSize / 2f;
                    float dotY = mapCenter.Y + relY - DotSize / 2f;

                    // Skip if outside minimap bounds
                    if (dotX < MapX || dotX + DotSize > MapX + MapSize ||
                        dotY < MapY || dotY + DotSize > MapY + MapSize)
                        continue;

                    var tileColor = chunk.Tiles[row, col].TileColor();
                    var dotRect   = new Rectangle((int)dotX, (int)dotY, DotSize, DotSize);
                    spriteBatch.Draw(spriteManager.GetPixel(tileColor), dotRect, Color.White);
                }
            }
        }

        // Player dot — always at center of minimap
        int pdX = (int)(mapCenter.X - PlayerDotSize / 2f);
        int pdY = (int)(mapCenter.Y - PlayerDotSize / 2f);
        var playerRect = new Rectangle(pdX, pdY, PlayerDotSize, PlayerDotSize);
        spriteBatch.Draw(spriteManager.GetPixel(Color.White), playerRect, Color.White);
    }

    private static void DrawBorder(SpriteBatch sb, SpriteManager sm, Rectangle rect, Color color, int thickness)
    {
        var tex = sm.GetPixel(color);
        sb.Draw(tex, new Rectangle(rect.X, rect.Y, rect.Width, thickness), Color.White);
        sb.Draw(tex, new Rectangle(rect.X, rect.Bottom - thickness, rect.Width, thickness), Color.White);
        sb.Draw(tex, new Rectangle(rect.X, rect.Y, thickness, rect.Height), Color.White);
        sb.Draw(tex, new Rectangle(rect.Right - thickness, rect.Y, thickness, rect.Height), Color.White);
    }
}
