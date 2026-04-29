using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

public class Button : UIElement
{
    public string  Text    { get; set; }
    public Action? OnClick { get; set; }

    private bool _hovered;
    private bool _pressed;
    private bool _prevPressed;

    public Button(string text, Rectangle bounds)
    {
        Text   = text;
        Bounds = bounds;
    }

    public override void Update(GameTime gameTime, MouseState mouse)
    {
        if (!Visible) return;

        _hovered = Bounds.Contains(mouse.X, mouse.Y);

        bool currentlyPressed = _hovered && mouse.LeftButton == ButtonState.Pressed;

        // Fire click on mouse-button release while hovered
        if (_prevPressed && !currentlyPressed && _hovered)
            OnClick?.Invoke();

        _pressed     = currentlyPressed;
        _prevPressed = currentlyPressed;
    }

    public override void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font)
    {
        if (!Visible) return;

        Color bgColor = _pressed  ? UITheme.ButtonPressed
                      : _hovered  ? UITheme.ButtonHover
                                  : UITheme.ButtonNormal;

        // Background
        spriteBatch.Draw(spriteManager.GetPixel(bgColor), Bounds, Color.White);

        // Border (4 single-pixel strips)
        DrawBorder(spriteBatch, spriteManager, UITheme.PanelBorder, 2);

        // Centered text
        if (font != null && !string.IsNullOrEmpty(Text))
        {
            var textSize = font.MeasureString(Text);
            var textPos  = new Vector2(
                Bounds.X + (Bounds.Width  - textSize.X) / 2f,
                Bounds.Y + (Bounds.Height - textSize.Y) / 2f);
            spriteBatch.DrawString(font, Text, textPos, UITheme.TextPrimary);
        }
    }

    private void DrawBorder(SpriteBatch sb, SpriteManager sm, Color color, int thickness)
    {
        var tex = sm.GetPixel(color);
        // Top
        sb.Draw(tex, new Rectangle(Bounds.X, Bounds.Y, Bounds.Width, thickness), Color.White);
        // Bottom
        sb.Draw(tex, new Rectangle(Bounds.X, Bounds.Bottom - thickness, Bounds.Width, thickness), Color.White);
        // Left
        sb.Draw(tex, new Rectangle(Bounds.X, Bounds.Y, thickness, Bounds.Height), Color.White);
        // Right
        sb.Draw(tex, new Rectangle(Bounds.Right - thickness, Bounds.Y, thickness, Bounds.Height), Color.White);
    }
}
