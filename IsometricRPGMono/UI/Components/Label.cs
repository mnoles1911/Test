using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

public class Label : UIElement
{
    public string Text      { get; set; }
    public Color  TextColor { get; set; } = UITheme.TextPrimary;
    public float  Scale     { get; set; } = 1f;

    public Label(string text, Rectangle bounds)
    {
        Text   = text;
        Bounds = bounds;
    }

    public override void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font)
    {
        if (!Visible || font == null || string.IsNullOrEmpty(Text)) return;

        spriteBatch.DrawString(
            font,
            Text,
            new Vector2(Bounds.X, Bounds.Y),
            TextColor,
            0f,
            Vector2.Zero,
            Scale,
            SpriteEffects.None,
            0f);
    }
}
