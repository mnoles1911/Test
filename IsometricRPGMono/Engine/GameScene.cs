using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

/// <summary>
/// Main gameplay class. Owns all subsystems and orchestrates the game loop.
/// Replaces the SpriteKit GameScene.
/// </summary>
public class GameScene
{
    // ---- Subsystems ----
    public Player        Player        { get; private set; } = null!;
    public List<Enemy>   Enemies       { get; }              = new List<Enemy>();
    public CombatSystem  CombatSystem  { get; private set; } = null!;
    public ItemSpawner   ItemSpawner   { get; private set; } = null!;
    public WorldManager  WorldManager  { get; private set; } = null!;
    public InputManager  InputManager  { get; private set; } = null!;

    // ---- Camera ----
    /// The screen-space position the camera is centred on (passed to all Draw calls).
    public Vector2 CameraPos { get; private set; }

    // ---- Timing / state ----
    private double _totalTime;
    private double _enemySpawnTimer;
    private int    _killCount;

    private SeededRNG _rng = new SeededRNG(Constants.WorldSeed ^ 0xDEADBEEF);

    // ---- Viewport (set from GraphicsDevice in Initialize) ----
    private int _viewportWidth  = 1280;
    private int _viewportHeight = 720;

    // -------------------------------------------------------------------------

    public void Initialize(GraphicsDevice graphicsDevice)
    {
        _viewportWidth  = graphicsDevice.Viewport.Width;
        _viewportHeight = graphicsDevice.Viewport.Height;

        InputManager  = new InputManager();
        WorldManager  = new WorldManager();
        CombatSystem  = new CombatSystem();
        ItemSpawner   = new ItemSpawner();

        // Spawn player at chunk centre
        Player = new Player(new Vector2(8f, 8f));

        // Load initial chunks around player
        WorldManager.InitialLoad(Player.WorldPosition);

        // Spawn items in the initially loaded chunks
        var context = BuildGameContext();
        foreach (var chunk in WorldManager.ChunksNeedingItemSpawn())
            ItemSpawner.SpawnItemsForChunk(chunk, context, _rng);

        // Camera starts centred on the player
        CameraPos = IsometricMath.WorldToScreen(Player.WorldPosition);
    }

    public void LoadContent(SpriteManager spriteManager)
    {
        // WorldRenderer is constructed here since it needs PrimitiveRenderer,
        // which is owned by Game1; we receive it in Draw.  Nothing to preload.
    }

    // -------------------------------------------------------------------------
    // Game loop

    public void Update(GameTime gameTime, KeyboardState keyboard, MouseState mouse)
    {
        double dt          = gameTime.ElapsedGameTime.TotalSeconds;
        _totalTime         = gameTime.TotalGameTime.TotalSeconds;

        // Clamp dt so spiral-of-death is avoided
        dt = Math.Min(dt, 1.0 / 30.0);

        // 1. Input
        var playerScreenPos = new Vector2(
            _viewportWidth  / 2f + (IsometricMath.WorldToScreen(Player.WorldPosition) - CameraPos).X,
            _viewportHeight / 2f + (IsometricMath.WorldToScreen(Player.WorldPosition) - CameraPos).Y);
        InputManager.Update(keyboard, mouse, playerScreenPos);

        // 2. Player movement + collision
        var oldPos = Player.WorldPosition;
        Player.Move(InputManager.MovementDirection, dt);

        if (!WorldManager.IsWalkable(oldPos, Player.WorldPosition))
        {
            var slideX = new Vector2(Player.WorldPosition.X, oldPos.Y);
            var slideY = new Vector2(oldPos.X, Player.WorldPosition.Y);

            if (WorldManager.IsWalkable(oldPos, slideX))
                Player.WorldPosition = slideX;
            else if (WorldManager.IsWalkable(oldPos, slideY))
                Player.WorldPosition = slideY;
            else
                Player.WorldPosition = oldPos;
        }

        Player.Update(gameTime);   // ticks buffs and hit-flash

        // 3. Fire bullet
        if (InputManager.FireHeld && Player.CanFire(_totalTime))
        {
            var aimDir = InputManager.AimDirection;
            if (aimDir.LengthSquared() > 0.01f)
            {
                // Convert screen-space aim direction to isometric world direction
                var worldDir = IsometricMath.ScreenToWorld(aimDir) - IsometricMath.ScreenToWorld(Vector2.Zero);
                if (worldDir.LengthSquared() > 1e-6f)
                {
                    worldDir = Vector2.Normalize(worldDir);
                    CombatSystem.FireBullet(Player.WorldPosition, worldDir, _totalTime);
                    Player.DidFire(_totalTime);
                }
            }
        }

        // 4. Enemies: AI + update
        foreach (var enemy in Enemies)
        {
            if (!enemy.IsAlive) continue;
            enemy.UpdateAI(Player.WorldPosition, _totalTime, WorldManager);
            enemy.Update(gameTime);

            // Enemy melee attack
            if (enemy.CanAttack(_totalTime))
            {
                Player.TakeDamage(Constants.EnemyAttackDamage);
                enemy.LastAttackTime = _totalTime;
            }
        }

        // 5. Combat (bullets)
        CombatSystem.Update(dt, _totalTime, Enemies, Player);

        // 6. Item attraction / collection
        ItemSpawner.Update(dt, Player);

        // 7. World streaming
        var (loaded, unloaded) = WorldManager.UpdateAroundPlayer(Player.WorldPosition);

        if (loaded.Count > 0)
        {
            var context = BuildGameContext();
            foreach (var coord in loaded)
            {
                if (WorldManager.LoadedChunks.TryGetValue(coord, out var chunk))
                    ItemSpawner.SpawnItemsForChunk(chunk, context, _rng);
            }
        }

        foreach (var coord in unloaded)
        {
            ItemSpawner.RemoveItemsInChunk(coord);
            RemoveEnemiesInChunk(coord);
        }

        // 8. Enemy spawning
        _enemySpawnTimer += dt;
        if (_enemySpawnTimer >= Constants.EnemySpawnInterval)
        {
            _enemySpawnTimer = 0;
            TrySpawnEnemies();
        }

        // 9. Remove dead enemies, award XP
        var newlyDead = Enemies.Where(e => !e.IsAlive).ToList();
        foreach (var dead in newlyDead)
            _killCount++;
        Enemies.RemoveAll(e => !e.IsAlive);

        // 10. Camera: lerp toward player screen position
        var targetCam = IsometricMath.WorldToScreen(Player.WorldPosition);
        CameraPos = Vector2.Lerp(CameraPos, targetCam, 0.1f);
    }

    // ---- World renderer (lazy-created on first Draw) ----
    private WorldRenderer? _worldRenderer;

    // -------------------------------------------------------------------------
    // Drawing

    public void Draw(
        GameTime          gameTime,
        SpriteBatch       spriteBatch,
        PrimitiveRenderer primRenderer,
        SpriteManager     spriteManager,
        Vector2           cameraPos)
    {
        // 1. World tiles (uses PrimitiveRenderer, must be before SpriteBatch.Begin)
        _worldRenderer ??= new WorldRenderer(primRenderer);
        _worldRenderer.Draw(WorldManager, cameraPos);

        // 2. Sprite pass
        spriteBatch.Begin(
            sortMode:        SpriteSortMode.Deferred,
            blendState:      BlendState.AlphaBlend,
            samplerState:    SamplerState.PointClamp,
            transformMatrix: Matrix.Identity);

        ItemSpawner.Draw(spriteBatch, spriteManager, cameraPos);

        foreach (var enemy in Enemies)
            enemy.Draw(spriteBatch, spriteManager, cameraPos);

        Player.Draw(spriteBatch, spriteManager, cameraPos);

        CombatSystem.Draw(spriteBatch, spriteManager, cameraPos);

        spriteBatch.End();
    }

    private void TrySpawnEnemies()
    {
        int aliveCount = Enemies.Count(e => e.IsAlive);
        if (aliveCount >= Constants.MaxTotalEnemies) return;

        var playerChunk = ChunkCoord.FromWorld(
            (int)MathF.Floor(Player.WorldPosition.X),
            (int)MathF.Floor(Player.WorldPosition.Y));

        foreach (var (coord, chunk) in WorldManager.LoadedChunks)
        {
            int dist = coord.ChebyshevDistance(playerChunk);
            if (dist < 1 || dist > 2) continue;

            int chunkEnemies = Enemies.Count(e => e.IsAlive &&
                ChunkCoord.FromWorld(
                    (int)MathF.Floor(e.WorldPosition.X),
                    (int)MathF.Floor(e.WorldPosition.Y)) == coord);

            if (chunkEnemies >= Constants.MaxEnemiesPerChunk) continue;

            var positions = chunk.Rooms.Count > 0
                ? chunk.WalkableRoomPositions()
                : chunk.WalkablePositions();

            if (positions.Count == 0) continue;

            var pick = positions[(int)(_rng.Next() % (ulong)positions.Count)];
            var pos  = new Vector2(pick.worldCol + 0.5f, pick.worldRow + 0.5f);

            // Don't spawn too close to player
            if (IsometricMath.Distance(pos, Player.WorldPosition) < 4f) continue;

            var enemy = new Enemy(pos);

            // Scale difficulty by distance from origin and player level
            float distFromOrigin = IsometricMath.Distance(pos, Vector2.Zero);
            float scaling = 1f + (distFromOrigin / 20f) + (Player.Level - 1) * 0.2f;
            enemy.Health    = (int)(Constants.EnemyMaxHealth * scaling);
            enemy.MaxHealth = enemy.Health;

            Enemies.Add(enemy);
            break; // one spawn per interval
        }
    }

    private void RemoveEnemiesInChunk(ChunkCoord coord)
    {
        Enemies.RemoveAll(e =>
        {
            var ec = ChunkCoord.FromWorld(
                (int)MathF.Floor(e.WorldPosition.X),
                (int)MathF.Floor(e.WorldPosition.Y));
            return ec == coord;
        });
    }

    private GameContext BuildGameContext()
    {
        return new GameContext
        {
            PlayerLevel    = Player?.Level    ?? 1,
            EnemiesKilled  = _killCount,
            Flags          = new List<string>()
        };
    }
}
