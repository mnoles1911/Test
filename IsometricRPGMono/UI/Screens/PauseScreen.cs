using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

/// <summary>
/// Pause screen: semi-transparent overlay with Resume and Main Menu buttons.
/// </summary>
public class PauseScreen : UIScreen
{
    public Action? OnResume   { get; set; }
    public Action? OnMainMenu { get; set; }

    private const int ScreenW = 1280;
    private const int ScreenH = 720;

    private const int PanelW = 320;
    private const int PanelH = 240;
    private const int ButtonW = 240;
    private const int ButtonH = 50;
    private const int ButtonSpacing = 14;

    private readonly Panel  _panel;
    private readonly Button _resumeBtn;
    private readonly Button _mainMenuBtn;

    public PauseScreen()
    {
        int panelX = (ScreenW - PanelW) / 2;
        int panelY = (ScreenH - PanelH) / 2;

        _panel = new Panel(new Rectangle(panelX, panelY, PanelW, PanelH));

        int btnX = panelX + (PanelW - ButtonW) / 2;
        int totalH = ButtonH * 2 + ButtonSpacing;
        int btnStartY = panelY + (PanelH - totalH) / 2 + 20; // leave room for title

        _resumeBtn = new Button("Resume",
            new Rectangle(btnX, btnStartY, ButtonW, ButtonH))
        {
            OnClick = () => OnResume?.Invoke()
        };

        _mainMenuBtn = new Button("Main Menu",
            new Rectangle(btnX, btnStartY + ButtonH + ButtonSpacing, ButtonW, ButtonH))
        {
            OnClick = () => OnMainMenu?.Invoke()
        };
    }

    public override void Update(GameTime gameTime, MouseState mouse, KeyboardState keyboard)
    {
        _resumeBtn.Update(gameTime, mouse);
        _mainMenuBtn.Update(gameTime, mouse);

        // Escape also resumes
        if (keyboard.IsKeyDown(Keys.Escape))
        {
            // Handled in GameScene to avoid double-triggering; no-op here
        }
    }

    public override void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font)
    {
        // Semi-transparent full-screen overlay
        spriteBatch.Draw(
            spriteManager.GetPixel(UITheme.Overlay),
            new Rectangle(0, 0, ScreenW, ScreenH),
            Color.White);

        // Panel
        _panel.Draw(spriteBatch, spriteManager, font);

        // "PAUSED" title centered at top of panel
        if (font != null)
        {
            var sz  = font.MeasureString("PAUSED");
            var pos = new Vector2(
                _panel.Bounds.X + (_panel.Bounds.Width - sz.X) / 2f,
                _panel.Bounds.Y + 16);
            spriteBatch.DrawString(font, "PAUSED", pos, UITheme.Gold);
        }

        // Buttons
        _resumeBtn.Draw(spriteBatch, spriteManager, font);
        _mainMenuBtn.Draw(spriteBatch, spriteManager, font);
    }
}
