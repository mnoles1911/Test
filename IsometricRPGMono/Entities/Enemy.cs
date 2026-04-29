using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace IsometricRPG;

public enum EnemyState { Idle, Chasing, Attacking }

public class Enemy : Entity
{
    public EnemyState State          { get; private set; } = EnemyState.Idle;
    public double     LastAttackTime { get; set; }
    public int        XPReward       { get; set; } = 15;

    public Enemy(Vector2 worldPosition)
        : base(worldPosition, Constants.EnemyMaxHealth) { }

    /// Main AI tick. Call every frame with the current player world position, game time, and delta time.
    public void UpdateAI(Vector2 playerWorldPos, double currentTime, WorldManager world, double deltaTime)
    {
        float dist = IsometricMath.Distance(WorldPosition, playerWorldPos);

        // Convert pixel ranges to tile units
        float detectionTiles = Constants.EnemyDetectionRange / Constants.TileWidth;
        float attackTiles    = Constants.EnemyAttackRange    / Constants.TileWidth;

        if (dist > detectionTiles)
        {
            State = EnemyState.Idle;
            return;
        }

        if (dist <= attackTiles)
        {
            State = EnemyState.Attacking;
            return;
        }

        // Chasing
        State = EnemyState.Chasing;
        MoveToward(playerWorldPos, world, deltaTime);
    }

    private void MoveToward(Vector2 target, WorldManager world, double deltaTime)
    {
        var dir    = IsometricMath.Direction(WorldPosition, target);
        float step = (Constants.EnemySpeed / Constants.TileWidth) * (float)deltaTime;
        var desired = WorldPosition + dir * step;

        // Wall-slide
        if (world.IsWalkable(WorldPosition, desired))
        {
            WorldPosition = desired;
        }
        else
        {
            var slideX = new Vector2(desired.X, WorldPosition.Y);
            var slideY = new Vector2(WorldPosition.X, desired.Y);
            if (world.IsWalkable(WorldPosition, slideX))
                WorldPosition = slideX;
            else if (world.IsWalkable(WorldPosition, slideY))
                WorldPosition = slideY;
        }
    }

    public bool CanAttack(double currentTime)
        => State == EnemyState.Attacking
           && (currentTime - LastAttackTime) >= Constants.EnemyAttackCooldown;

    public override void Update(GameTime gameTime)
    {
        base.Update(gameTime);
    }

    public override void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, Vector2 cameraPos)
    {
        var screenPos = ScreenPosition - cameraPos;
        var size = Constants.EnemySize;

        // Body circle
        int diameter = (int)Math.Max(size.X, size.Y);
        var bodyColor = TintColor == Color.White ? new Color(180, 60, 60) : TintColor;  // dull red
        var circleTex = spriteManager.GetCircle(diameter, bodyColor);

        spriteBatch.Draw(
            circleTex,
            new Vector2(screenPos.X - diameter / 2f, screenPos.Y - diameter / 2f),
            Color.White);

        // Health bar
        DrawHealthBar(spriteBatch, spriteManager, screenPos, size);
    }

    private void DrawHealthBar(SpriteBatch sb, SpriteManager sm, Vector2 screenPos, Vector2 size)
    {
        const int barW = 22, barH = 3;
        float ratio = Math.Max(0f, (float)Health / MaxHealth);
        var bgTex   = sm.GetRect(barW, barH, new Color(60, 60, 60));
        var fgColor = ratio > 0.5f ? Color.Green : (ratio > 0.25f ? Color.Yellow : Color.Red);
        var fgTex   = sm.GetRect(Math.Max(1, (int)(barW * ratio)), barH, fgColor);

        var barOrigin = new Vector2(screenPos.X - barW / 2f, screenPos.Y - size.Y / 2f - 7f);
        sb.Draw(bgTex, barOrigin, Color.White);
        if (ratio > 0f)
            sb.Draw(fgTex, barOrigin, Color.White);
    }
}
