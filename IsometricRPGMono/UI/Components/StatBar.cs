using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

public class StatBar : UIElement
{
    public float   Value     { get; set; }
    public float   MaxValue  { get; set; }
    public Color   FillColor { get; set; } = UITheme.HealthBar;
    public Color   BackColor { get; set; } = new Color(30, 30, 30);
    public string? Label     { get; set; }

    public StatBar(Rectangle bounds)
    {
        Bounds = bounds;
    }

    public override void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font)
    {
        if (!Visible) return;

        // Background
        spriteBatch.Draw(spriteManager.GetPixel(BackColor), Bounds, Color.White);

        // Fill proportional to Value/MaxValue
        if (MaxValue > 0f && Value > 0f)
        {
            float ratio    = Math.Clamp(Value / MaxValue, 0f, 1f);
            int   fillW    = Math.Max(1, (int)(Bounds.Width * ratio));
            var   fillRect = new Rectangle(Bounds.X, Bounds.Y, fillW, Bounds.Height);
            spriteBatch.Draw(spriteManager.GetPixel(FillColor), fillRect, Color.White);
        }

        // Optional label centered in bar
        if (font != null && !string.IsNullOrEmpty(Label))
        {
            var textSize = font.MeasureString(Label);
            var textPos  = new Vector2(
                Bounds.X + (Bounds.Width  - textSize.X) / 2f,
                Bounds.Y + (Bounds.Height - textSize.Y) / 2f);
            spriteBatch.DrawString(font, Label, textPos, UITheme.TextPrimary);
        }
    }
}
