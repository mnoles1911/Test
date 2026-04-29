using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

/// <summary>
/// Abstract base for all full-screen or overlay UI screens.
/// </summary>
public abstract class UIScreen
{
    public abstract void Update(GameTime gameTime, MouseState mouse, KeyboardState keyboard);
    public abstract void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font);
}

/// <summary>
/// Stack-based manager — top screen receives input and is drawn last (on top).
/// </summary>
public class ScreenManager
{
    private readonly Stack<UIScreen> _screens = new Stack<UIScreen>();

    public bool IsEmpty => _screens.Count == 0;

    public void Push(UIScreen screen)
    {
        _screens.Push(screen);
    }

    public void Pop()
    {
        if (_screens.Count > 0)
            _screens.Pop();
    }

    public UIScreen? Peek() => _screens.Count > 0 ? _screens.Peek() : null;

    public void Update(GameTime gameTime, MouseState mouse, KeyboardState keyboard)
    {
        if (_screens.Count > 0)
            _screens.Peek().Update(gameTime, mouse, keyboard);
    }

    public void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font)
    {
        // Draw all screens bottom-to-top so the top screen is rendered last
        var list = _screens.ToArray();
        for (int i = list.Length - 1; i >= 0; i--)
            list[i].Draw(spriteBatch, spriteManager, font);
    }
}
