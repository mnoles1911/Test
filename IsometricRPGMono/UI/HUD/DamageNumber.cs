using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace IsometricRPG;

public class DamageNumber
{
    private const double Lifetime = 1.2;
    private const float  RiseSpeed = 30f; // pixels per second

    public Vector2 ScreenPos { get; private set; }
    public string  Text      { get; }
    public Color   Color     { get; }
    public float   Alpha     { get; private set; } = 1f;

    public bool IsExpired => Alpha <= 0f;

    private double _timer;

    public DamageNumber(Vector2 screenPos, string text, Color color)
    {
        ScreenPos = screenPos;
        Text      = text;
        Color     = color;
    }

    public void Update(GameTime gameTime)
    {
        double dt = gameTime.ElapsedGameTime.TotalSeconds;
        _timer += dt;

        // Rise upward
        ScreenPos = new Vector2(ScreenPos.X, ScreenPos.Y - RiseSpeed * (float)dt);

        // Fade out linearly over lifetime
        Alpha = Math.Max(0f, 1f - (float)(_timer / Lifetime));
    }

    public void Draw(SpriteBatch spriteBatch, SpriteFont? font)
    {
        if (font == null || IsExpired) return;
        var drawColor = Color * Alpha;
        spriteBatch.DrawString(font, Text, ScreenPos, drawColor);
    }
}

public class DamageNumberManager
{
    private readonly List<DamageNumber> _numbers = new List<DamageNumber>();

    public void Spawn(Vector2 screenPos, int damage, Color color)
    {
        _numbers.Add(new DamageNumber(screenPos, damage.ToString(), color));
    }

    public void Update(GameTime gameTime)
    {
        foreach (var n in _numbers)
            n.Update(gameTime);
        _numbers.RemoveAll(n => n.IsExpired);
    }

    public void Draw(SpriteBatch spriteBatch, SpriteFont? font)
    {
        foreach (var n in _numbers)
            n.Draw(spriteBatch, font);
    }
}
