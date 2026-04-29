using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace IsometricRPG;

public class Bullet
{
    public Vector2 WorldPosition { get; set; }

    /// Velocity in world-tile units per second.
    public Vector2 Velocity      { get; }

    public double SpawnTime      { get; }
    public int    Damage         { get; }
    public bool   IsExpired      { get; set; }

    public Bullet(Vector2 worldPosition, Vector2 direction, double spawnTime, int damage)
    {
        WorldPosition = worldPosition;
        SpawnTime     = spawnTime;
        Damage        = damage;

        // Convert bullet speed (pixels/s) to tile-units/s
        float speedInTiles = Constants.BulletSpeed / Constants.TileWidth;
        Velocity = Vector2.Normalize(direction) * speedInTiles;
    }

    public void Update(double deltaTime, double currentTime)
    {
        WorldPosition += Velocity * (float)deltaTime;

        if (currentTime - SpawnTime > Constants.BulletLifetime)
            IsExpired = true;
    }

    /// Returns true if the bullet overlaps the entity (within ~0.55 tile, small margin for float imprecision).
    public bool CheckHit(Entity target)
        => IsometricMath.Distance(WorldPosition, target.WorldPosition) < 0.55f;

    public void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, Vector2 cameraPos)
    {
        const int diameter = 8;
        var tex       = spriteManager.GetCircle(diameter, Color.Yellow);
        var screenPos = IsometricMath.WorldToScreen(WorldPosition) - cameraPos;
        spriteBatch.Draw(tex,
            new Vector2(screenPos.X - diameter / 2f, screenPos.Y - diameter / 2f),
            Color.White);
    }
}
