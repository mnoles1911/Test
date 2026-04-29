using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

public class Panel : UIElement
{
    public Color BackgroundColor { get; set; } = UITheme.Panel;
    public Color BorderColor     { get; set; } = UITheme.PanelBorder;
    public bool  ShowBorder      { get; set; } = true;
    public List<UIElement> Children { get; } = new List<UIElement>();

    public Panel(Rectangle bounds)
    {
        Bounds = bounds;
    }

    public override void Update(GameTime gameTime, MouseState mouse)
    {
        if (!Visible) return;
        foreach (var child in Children)
            child.Update(gameTime, mouse);
    }

    public override void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font)
    {
        if (!Visible) return;

        // Background
        spriteBatch.Draw(spriteManager.GetPixel(BackgroundColor), Bounds, Color.White);

        // Border (4 single-pixel strips, 2 px thick)
        if (ShowBorder)
        {
            const int t = 2;
            var tex = spriteManager.GetPixel(BorderColor);
            spriteBatch.Draw(tex, new Rectangle(Bounds.X, Bounds.Y, Bounds.Width, t), Color.White);
            spriteBatch.Draw(tex, new Rectangle(Bounds.X, Bounds.Bottom - t, Bounds.Width, t), Color.White);
            spriteBatch.Draw(tex, new Rectangle(Bounds.X, Bounds.Y, t, Bounds.Height), Color.White);
            spriteBatch.Draw(tex, new Rectangle(Bounds.Right - t, Bounds.Y, t, Bounds.Height), Color.White);
        }

        // Children
        foreach (var child in Children)
            child.Draw(spriteBatch, spriteManager, font);
    }
}
