using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace IsometricRPG;

/// Base class for all game entities (player, enemies).
/// Pure data – no scene graph nodes. Rendering is done externally.
public class Entity
{
    /// World position in tile units (float).
    public Vector2 WorldPosition { get; set; }

    public int Health    { get; set; }
    public int MaxHealth { get; set; }

    public bool IsAlive => Health > 0;

    /// Current tint applied when drawing (used for hit flash).
    public Color TintColor { get; protected set; } = Color.White;

    /// Remaining seconds of hit-flash.
    public double HitFlashTimer { get; protected set; }

    public Entity(Vector2 worldPosition, int maxHealth)
    {
        WorldPosition = worldPosition;
        MaxHealth     = maxHealth;
        Health        = maxHealth;
    }

    public virtual void TakeDamage(int amount)
    {
        Health = Math.Max(0, Health - amount);
        TintColor    = Color.Red;
        HitFlashTimer = 0.1;
    }

    public virtual void Update(GameTime gameTime)
    {
        if (HitFlashTimer > 0)
        {
            HitFlashTimer -= gameTime.ElapsedGameTime.TotalSeconds;
            if (HitFlashTimer <= 0)
            {
                HitFlashTimer = 0;
                TintColor = Color.White;
            }
        }
    }

    public virtual void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, Vector2 cameraPos)
    {
        // Base entities draw nothing – subclasses override.
    }

    // Convenience: screen-space position (no camera offset applied here; callers subtract cameraPos).
    public Vector2 ScreenPosition => IsometricMath.WorldToScreen(WorldPosition);
}
