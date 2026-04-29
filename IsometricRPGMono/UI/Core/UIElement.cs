using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

public abstract class UIElement
{
    public Rectangle Bounds  { get; set; }
    public bool      Visible { get; set; } = true;

    public virtual void Update(GameTime gameTime, MouseState mouse) { }
    public virtual void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font) { }
}
