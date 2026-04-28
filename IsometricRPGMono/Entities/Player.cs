using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace IsometricRPG;

public enum BuffType { Speed, Damage, Shield, FireRate, XpBoost }

public struct ActiveBuff
{
    public BuffType Type       { get; set; }
    public float    Multiplier { get; set; }
    public double   Duration   { get; set; }
    public double   Remaining  { get; set; }
}

public class Player : Entity
{
    // Inventory: 20 nullable slots
    public List<Item?> Inventory  { get; } = new List<Item?>(new Item?[20]);
    public EquipmentSet Equipment  { get; } = new EquipmentSet();

    public int    Level          { get; private set; } = 1;
    public double XP             { get; private set; } = 0;
    public double XPToNextLevel  => 100.0 * Math.Pow(1.5, Level - 1);

    private double _lastFireTime = 0;
    private readonly List<ActiveBuff> _buffs = new List<ActiveBuff>();

    public IReadOnlyList<ActiveBuff> ActiveBuffs => _buffs;
    public int ActiveBuffCount => _buffs.Count;

    public Player(Vector2 worldPosition)
        : base(worldPosition, Constants.PlayerMaxHealth) { }

    // ---- Buff System ----

    public void ApplyBuff(BuffType type, float multiplier, double duration)
    {
        _buffs.RemoveAll(b => b.Type == type);
        _buffs.Add(new ActiveBuff { Type = type, Multiplier = multiplier,
                                    Duration = duration, Remaining = duration });
    }

    public void UpdateBuffs(double deltaTime)
    {
        for (int i = 0; i < _buffs.Count; i++)
        {
            var b = _buffs[i];
            b.Remaining -= deltaTime;
            _buffs[i] = b;
        }
        _buffs.RemoveAll(b => b.Remaining <= 0);
    }

    /// Returns the product of all active multipliers for the given buff type (1.0 if none).
    public float BuffMultiplier(BuffType type)
    {
        float product = 1f;
        foreach (var b in _buffs)
            if (b.Type == type) product *= b.Multiplier;
        return product;
    }

    // ---- Combat ----

    public bool CanFire(double currentTime)
    {
        double rateMultiplier = BuffMultiplier(BuffType.FireRate);
        double effectiveRate  = Constants.FireRate * rateMultiplier;
        return (currentTime - _lastFireTime) >= effectiveRate;
    }

    public void DidFire(double currentTime)
    {
        _lastFireTime = currentTime;
    }

    public float EffectiveDamage() => Constants.BulletDamage * BuffMultiplier(BuffType.Damage);

    public float EffectiveSpeed() => Constants.PlayerSpeed * BuffMultiplier(BuffType.Speed);

    // ---- XP / Level ----

    public void AddXP(double amount)
    {
        double boosted = amount * BuffMultiplier(BuffType.XpBoost);
        XP += boosted;
        while (XP >= XPToNextLevel)
        {
            XP -= XPToNextLevel;
            Level++;
            MaxHealth += 10;
            Health = MaxHealth;
        }
    }

    // ---- Inventory helpers ----

    public bool AddToInventory(Item item)
    {
        for (int i = 0; i < Inventory.Count; i++)
        {
            if (Inventory[i] == null)
            {
                Inventory[i] = item;
                return true;
            }
        }
        return false;
    }

    // ---- Update / Draw ----

    public override void Update(GameTime gameTime)
    {
        base.Update(gameTime);
        UpdateBuffs(gameTime.ElapsedGameTime.TotalSeconds);
    }

    /// Move player in world-space using the pre-computed direction and deltaTime.
    /// Wall-slide collision is handled in GameScene.
    public void Move(Vector2 direction, double deltaTime)
    {
        if (direction.LengthSquared() < 1e-6f) return;
        float speed  = EffectiveSpeed();
        WorldPosition += direction * speed * (float)deltaTime / Constants.TileWidth;
    }

    public override void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, Vector2 cameraPos)
    {
        var screenPos = ScreenPosition - cameraPos;
        var size = Constants.PlayerSize;

        // Body rectangle
        var tex = spriteManager.GetRect(
            (int)size.X,
            (int)size.Y,
            TintColor == Color.White ? new Color(70, 130, 180) : TintColor);  // steel blue

        spriteBatch.Draw(
            tex,
            new Vector2(screenPos.X - size.X / 2f, screenPos.Y - size.Y / 2f),
            Color.White);

        // Simple health bar
        DrawHealthBar(spriteBatch, spriteManager, screenPos, size);
    }

    private void DrawHealthBar(SpriteBatch sb, SpriteManager sm, Vector2 screenPos, Vector2 size)
    {
        const int barW = 24, barH = 4;
        float ratio = Math.Max(0f, (float)Health / MaxHealth);
        var bgTex   = sm.GetRect(barW, barH, new Color(60, 60, 60));
        var fgColor = ratio > 0.5f ? Color.Green : (ratio > 0.25f ? Color.Yellow : Color.Red);
        var fgTex   = sm.GetRect(Math.Max(1, (int)(barW * ratio)), barH, fgColor);

        var barOrigin = new Vector2(screenPos.X - barW / 2f, screenPos.Y - size.Y / 2f - 8f);
        sb.Draw(bgTex, barOrigin, Color.White);
        if (ratio > 0f)
            sb.Draw(fgTex, barOrigin, Color.White);
    }
}
