using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

/// <summary>
/// In-game HUD: health bar, XP bar, level label, kill counter, buff icons, damage numbers.
/// </summary>
public class GameHUD
{
    // ---- Bars ----
    private readonly StatBar _healthBar;
    private readonly StatBar _xpBar;

    // ---- Labels ----
    private readonly Label _levelLabel;
    private readonly Label _killLabel;

    // ---- Buff labels ----
    private readonly List<Label> _buffLabels = new List<Label>();

    // ---- Damage numbers ----
    public DamageNumberManager DamageNumbers { get; } = new DamageNumberManager();

    private const int BarLeft = 10;

    private readonly int _vpWidth;
    private readonly int _vpHeight;

    public GameHUD(int viewportWidth = 1280, int viewportHeight = 720)
    {
        _vpWidth  = viewportWidth;
        _vpHeight = viewportHeight;

        int barBottom = _vpHeight - 60;

        // Health bar: bottom-left, 200×20
        _healthBar = new StatBar(new Rectangle(BarLeft, barBottom, 200, 20))
        {
            FillColor = UITheme.HealthBar,
            BackColor = new Color(30, 30, 30)
        };

        // XP bar: below health bar, 200×12
        _xpBar = new StatBar(new Rectangle(BarLeft, barBottom + 26, 200, 12))
        {
            FillColor = UITheme.XPBar,
            BackColor = new Color(30, 30, 30)
        };

        // Level label: above health bar
        _levelLabel = new Label("Level 1", new Rectangle(BarLeft, barBottom - 20, 100, 16))
        {
            TextColor = UITheme.TextPrimary
        };

        // Kill counter: top-right
        _killLabel = new Label("Kills: 0", new Rectangle(_vpWidth - 110, 10, 100, 16))
        {
            TextColor = UITheme.TextPrimary
        };
    }

    public void Update(GameTime gameTime, MouseState mouse, Player player)
    {
        _healthBar.Value    = player.Health;
        _healthBar.MaxValue = player.MaxHealth;

        _xpBar.Value    = (float)player.XP;
        _xpBar.MaxValue = (float)player.XPToNextLevel;

        _levelLabel.Text = $"Level {player.Level}";

        // Refresh buff labels from player
        _buffLabels.Clear();
        int buffY = 80;
        foreach (var buff in player.ActiveBuffs)
        {
            _buffLabels.Add(new Label(buff.Type.ToString(), new Rectangle(10, buffY, 120, 16))
            {
                TextColor = UITheme.Gold
            });
            buffY += 18;
        }

        DamageNumbers.Update(gameTime);
    }

    public void SetKillCount(int kills)
    {
        _killLabel.Text = $"Kills: {kills}";
    }

    /// <summary>
    /// Convert a world position to screen position and spawn a damage number.
    /// </summary>
    public void ShowDamage(Vector2 worldPos, int damage, Vector2 cameraPos)
    {
        var screenPos = IsometricMath.WorldToScreen(worldPos) - cameraPos
                      + new Vector2(_vpWidth / 2f, _vpHeight / 2f);
        DamageNumbers.Spawn(screenPos, damage, UITheme.HealthBar);
    }

    public void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font, Player player)
    {
        // Bars
        _healthBar.Draw(spriteBatch, spriteManager, font);
        _xpBar.Draw(spriteBatch, spriteManager, font);

        // Bar labels (HP / XP to the right of each bar)
        if (font != null)
        {
            spriteBatch.DrawString(font, "HP",
                new Vector2(BarLeft + 206, _healthBar.Bounds.Y + 2), UITheme.HealthBar);
            spriteBatch.DrawString(font, "XP",
                new Vector2(BarLeft + 206, _xpBar.Bounds.Y + 1), UITheme.XPBar);
        }

        // Labels
        _levelLabel.Draw(spriteBatch, spriteManager, font);
        _killLabel.Draw(spriteBatch, spriteManager, font);

        // Buff icons
        foreach (var lbl in _buffLabels)
            lbl.Draw(spriteBatch, spriteManager, font);

        // Damage numbers
        if (font != null)
            DamageNumbers.Draw(spriteBatch, font);
    }
}
