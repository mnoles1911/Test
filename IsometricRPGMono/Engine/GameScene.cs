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

    // ---- Audio ----
    private AudioManager _audio = null!;

    // ---- UI ----
    private ScreenManager _screenManager = null!;
    private GameHUD       _hud           = null!;
    private Minimap       _minimap       = null!;

    // Current game state
    private GameState _state = GameState.MainMenu;

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

    // Previous keyboard state for edge detection in UI
    private KeyboardState _prevKeyboard;

    // -------------------------------------------------------------------------

    public void Initialize(GraphicsDevice graphicsDevice)
    {
        _viewportWidth  = graphicsDevice.Viewport.Width;
        _viewportHeight = graphicsDevice.Viewport.Height;

        InputManager  = new InputManager();
        WorldManager  = new WorldManager();
        CombatSystem  = new CombatSystem();
        ItemSpawner   = new ItemSpawner();

        // Audio subsystem
        _audio = new AudioManager();
        _audio.Initialize(graphicsDevice);

        // Apply persisted settings (volume levels, etc.)
        var settings = SaveManager.LoadSettings();
        _audio.ApplySettings(settings);

        // UI subsystems
        _hud           = new GameHUD(_viewportWidth, _viewportHeight);
        _minimap       = new Minimap();
        _screenManager = new ScreenManager();

        // Start at main menu
        PushMainMenu();
    }

    private void InitializeGameplay()
    {
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

        _killCount = 0;
    }

    public void LoadContent(SpriteManager spriteManager)
    {
        // Nothing to preload — all textures are procedural.
    }

    // -------------------------------------------------------------------------
    // Screen helpers

    private void PushMainMenu()
    {
        _state = GameState.MainMenu;
        _audio?.PlayMusic(MusicType.MainMenu);
        var menu = new MainMenuScreen
        {
            ContinueEnabled = HasSave,
            OnNewGame = () =>
            {
                _audio.PlaySound(SoundType.MenuClick);
                _audio.PlayMusic(MusicType.Gameplay);
                SaveManager.DeleteSave();
                InitializeGameplay();
                _screenManager.Pop();
                _state = GameState.Playing;
            },
            OnContinue = () =>
            {
                _audio.PlaySound(SoundType.MenuClick);
                _audio.PlayMusic(MusicType.Gameplay);
                // Prepare subsystems then restore saved state
                CombatSystem = new CombatSystem();
                ItemSpawner  = new ItemSpawner();
                Enemies.Clear();
                _enemySpawnTimer = 0;
                LoadGame();
                _screenManager.Pop();
                _state = GameState.Playing;
            },
            OnQuit = () =>
            {
                // Signal exit via a flag checked in Game1
                _wantsExit = true;
            }
        };
        _screenManager.Push(menu);
    }

    private bool _wantsExit = false;
    public bool WantsExit => _wantsExit;

    public bool HasSave => SaveManager.SaveExists;

    // -------------------------------------------------------------------------
    // Save / Load

    private void SaveGame()
    {
        if (Player == null) return;
        var data = new SaveData
        {
            PlayerStats  = new PlayerData
            {
                Level        = Player.Level,
                Experience   = (int)Player.XP,
                Health       = Player.Health,
                MaxHealth    = Player.MaxHealth,
                EnemiesKilled = _killCount,
            },
            Inventory    = new List<Item?>(Player.Inventory),
            Equipment    = Player.Equipment,
            Context      = BuildGameContext(),
            KillCount    = _killCount,
            PlayerWorldX = Player.WorldPosition.X,
            PlayerWorldY = Player.WorldPosition.Y,
        };
        SaveManager.SaveGame(data);
    }

    private void LoadGame()
    {
        var data = SaveManager.LoadGame();
        if (data == null) return;

        // Restore player position and stats
        Player = new Player(new Vector2(data.PlayerWorldX, data.PlayerWorldY));

        // RestoreProgress sets Level, MaxHealth, and resets Health to MaxHealth.
        // We then override Health from the save so the player isn't at full HP.
        Player.RestoreProgress(data.PlayerStats.Level, data.PlayerStats.Experience);
        Player.Health = Math.Clamp(data.PlayerStats.Health, 0, Player.MaxHealth);

        // Restore inventory (20 slots)
        var inv = data.Inventory;
        for (int i = 0; i < Player.Inventory.Count && i < inv.Count; i++)
            Player.Inventory[i] = inv[i];

        // Restore equipment slots
        Player.Equipment.Head.Equip(null!);   // clear first via helper
        RestoreEquipmentSlot(Player.Equipment.Head,     data.Equipment.Head);
        RestoreEquipmentSlot(Player.Equipment.Chest,    data.Equipment.Chest);
        RestoreEquipmentSlot(Player.Equipment.Legs,     data.Equipment.Legs);
        RestoreEquipmentSlot(Player.Equipment.Feet,     data.Equipment.Feet);
        RestoreEquipmentSlot(Player.Equipment.MainHand, data.Equipment.MainHand);
        RestoreEquipmentSlot(Player.Equipment.OffHand,  data.Equipment.OffHand);

        _killCount = data.KillCount;

        // Load world around restored position
        WorldManager.InitialLoad(Player.WorldPosition);
        var context = BuildGameContext();
        foreach (var chunk in WorldManager.ChunksNeedingItemSpawn())
            ItemSpawner.SpawnItemsForChunk(chunk, context, _rng);

        CameraPos = IsometricMath.WorldToScreen(Player.WorldPosition);
    }

    private static void RestoreEquipmentSlot(Equipment slot, Equipment saved)
    {
        if (saved.Item != null)
            slot.Equip(saved.Item);
        else
            slot.Unequip();
    }

    // -------------------------------------------------------------------------
    // Game loop

    public void Update(GameTime gameTime, KeyboardState keyboard, MouseState mouse)
    {
        double dt = gameTime.ElapsedGameTime.TotalSeconds;
        dt        = Math.Min(dt, 1.0 / 30.0);
        _totalTime = gameTime.TotalGameTime.TotalSeconds;

        // Always update screen manager (handles menus/pause)
        _screenManager.Update(gameTime, mouse, keyboard);

        // Always update audio (handles fade timers)
        _audio.Update(gameTime);

        if (_state == GameState.MainMenu || _state == GameState.GameOver)
        {
            _prevKeyboard = keyboard;
            return;
        }

        if (_state == GameState.Paused)
        {
            // Escape resumes
            if (keyboard.IsKeyDown(Keys.Escape) && !_prevKeyboard.IsKeyDown(Keys.Escape))
                ResumePlaying();
            _prevKeyboard = keyboard;
            return;
        }

        if (_state == GameState.Inventory)
        {
            // I or Escape closes inventory
            if ((keyboard.IsKeyDown(Keys.I) && !_prevKeyboard.IsKeyDown(Keys.I)) ||
                (keyboard.IsKeyDown(Keys.Escape) && !_prevKeyboard.IsKeyDown(Keys.Escape)))
            {
                CloseInventory();
            }
            _prevKeyboard = keyboard;
            return;
        }

        // ---- Playing state ----

        // 1. Input
        var playerScreenPos = new Vector2(
            _viewportWidth  / 2f + (IsometricMath.WorldToScreen(Player.WorldPosition) - CameraPos).X,
            _viewportHeight / 2f + (IsometricMath.WorldToScreen(Player.WorldPosition) - CameraPos).Y);
        InputManager.Update(keyboard, mouse, playerScreenPos);

        // 2. Check for pause (Escape)
        if (InputManager.PausePressed)
        {
            PushPause();
            _prevKeyboard = keyboard;
            return;
        }

        // 3. Check for inventory (I)
        if (InputManager.InventoryPressed)
        {
            PushInventory();
            _prevKeyboard = keyboard;
            return;
        }

        // 4. Player movement + collision
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

        Player.Update(gameTime);

        // 5. Fire bullet
        if (InputManager.FireHeld && Player.CanFire(_totalTime))
        {
            var aimDir = InputManager.AimDirection;
            if (aimDir.LengthSquared() > 0.01f)
            {
                var worldDir = IsometricMath.ScreenToWorld(aimDir) - IsometricMath.ScreenToWorld(Vector2.Zero);
                if (worldDir.LengthSquared() > 1e-6f)
                {
                    worldDir = Vector2.Normalize(worldDir);
                    _audio.PlaySound(SoundType.Shoot);
                    CombatSystem.FireBullet(Player.WorldPosition, worldDir, _totalTime);
                    Player.DidFire(_totalTime);
                }
            }
        }

        // 6. Enemies: AI + update
        foreach (var enemy in Enemies)
        {
            if (!enemy.IsAlive) continue;
            enemy.UpdateAI(Player.WorldPosition, _totalTime, WorldManager, dt);
            enemy.Update(gameTime);

            if (enemy.CanAttack(_totalTime))
            {
                _audio.PlaySound(SoundType.PlayerHurt);
                Player.TakeDamage(Constants.EnemyAttackDamage);
                enemy.LastAttackTime = _totalTime;
            }
        }

        // 7. Combat (bullets)
        // Snapshot enemy health before update to detect hits
        var preHealth = Enemies.Where(e => e.IsAlive)
            .ToDictionary(e => e, e => e.Health);

        CombatSystem.Update(dt, _totalTime, Enemies, Player);

        // Show damage numbers for enemies that took damage this frame; play hit SFX
        bool anyHit = false;
        foreach (var (enemy, prevHp) in preHealth)
        {
            int dmg = prevHp - enemy.Health;
            if (dmg > 0)
            {
                anyHit = true;
                _hud.ShowDamage(enemy.WorldPosition, dmg, CameraPos);
            }
        }
        if (anyHit)
            _audio.PlaySound(SoundType.Hit);

        // 8. Item attraction / collection
        int itemsBefore = ItemSpawner.Items.Count;
        ItemSpawner.Update(dt, Player);
        if (ItemSpawner.Items.Count < itemsBefore)
            _audio.PlaySound(SoundType.ItemPickup);

        // 9. World streaming
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

        // 10. Enemy spawning
        _enemySpawnTimer += dt;
        if (_enemySpawnTimer >= Constants.EnemySpawnInterval)
        {
            _enemySpawnTimer = 0;
            TrySpawnEnemies();
        }

        // 11. Remove dead enemies, award XP, play death SFX
        var newlyDead = Enemies.Where(e => !e.IsAlive).ToList();
        if (newlyDead.Count > 0)
            _audio.PlaySound(SoundType.EnemyDeath);
        int levelBefore = Player.Level;
        foreach (var dead in newlyDead)
        {
            _killCount++;
            Player.AddXP(20);
        }
        if (Player.Level > levelBefore)
            _audio.PlaySound(SoundType.LevelUp);
        Enemies.RemoveAll(e => !e.IsAlive);

        // 12. Update HUD
        _hud.Update(gameTime, mouse, Player);
        _hud.SetKillCount(_killCount);

        // 13. Check game over
        if (Player.Health <= 0 && _state == GameState.Playing)
        {
            PushGameOver();
        }

        // 14. Camera: lerp toward player screen position
        var targetCam = IsometricMath.WorldToScreen(Player.WorldPosition);
        CameraPos = Vector2.Lerp(CameraPos, targetCam, 0.1f);

        _prevKeyboard = keyboard;
    }

    // ---- Pause / Inventory / GameOver helpers ----

    private void PushPause()
    {
        _state = GameState.Paused;
        SaveGame();
        var pause = new PauseScreen
        {
            OnResume      = () => ResumePlaying(),
            OnMainMenu    = () => GoToMainMenu(),
            OnSaveAndQuit = () =>
            {
                SaveGame();
                GoToMainMenu();
            }
        };
        _screenManager.Push(pause);
    }

    private void ResumePlaying()
    {
        if (_state == GameState.Paused || _state == GameState.Inventory)
        {
            _screenManager.Pop();
            _state = GameState.Playing;
        }
    }

    private void PushInventory()
    {
        _state = GameState.Inventory;
        var inv = new InventoryScreen
        {
            Player  = Player,
            OnClose = () => CloseInventory()
        };
        _screenManager.Push(inv);
    }

    private void CloseInventory()
    {
        if (_state == GameState.Inventory)
        {
            _screenManager.Pop();
            _state = GameState.Playing;
        }
    }

    private void PushGameOver()
    {
        _state = GameState.GameOver;
        SaveGame();
        var go = new GameOverScreen
        {
            KillCount = _killCount,
            Level     = Player.Level,
            OnRestart = () =>
            {
                _screenManager.Pop();
                Enemies.Clear();
                CombatSystem  = new CombatSystem();
                ItemSpawner   = new ItemSpawner();
                _enemySpawnTimer = 0;
                InitializeGameplay();
                _state = GameState.Playing;
            },
            OnMainMenu = () => GoToMainMenu()
        };
        _screenManager.Push(go);
    }

    private void GoToMainMenu()
    {
        // Pop all screens then push main menu
        while (!_screenManager.IsEmpty)
            _screenManager.Pop();
        Enemies.Clear();
        PushMainMenu();
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
        Vector2           cameraPos,
        SpriteFont?       font = null)
    {
        if (_state == GameState.Playing || _state == GameState.Paused ||
            _state == GameState.Inventory)
        {
            // 1. World tiles
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

            // 3. HUD pass (new SpriteBatch pass on top)
            spriteBatch.Begin(
                sortMode:     SpriteSortMode.Deferred,
                blendState:   BlendState.AlphaBlend,
                samplerState: SamplerState.PointClamp);

            _hud.Draw(spriteBatch, spriteManager, font, Player);
            _minimap.Draw(spriteBatch, spriteManager, WorldManager, Player.WorldPosition, cameraPos);

            spriteBatch.End();
        }

        // 4. Screen manager pass (menus / overlays)
        if (!_screenManager.IsEmpty)
        {
            spriteBatch.Begin(
                sortMode:     SpriteSortMode.Deferred,
                blendState:   BlendState.AlphaBlend,
                samplerState: SamplerState.PointClamp);

            _screenManager.Draw(spriteBatch, spriteManager, font);

            spriteBatch.End();
        }
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

            if (IsometricMath.Distance(pos, Player.WorldPosition) < 4f) continue;

            var enemy = new Enemy(pos);

            float distFromOrigin = IsometricMath.Distance(pos, Vector2.Zero);
            float scaling = 1f + (distFromOrigin / 20f) + (Player.Level - 1) * 0.2f;
            enemy.Health    = (int)(Constants.EnemyMaxHealth * scaling);
            enemy.MaxHealth = enemy.Health;

            Enemies.Add(enemy);
            break;
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
