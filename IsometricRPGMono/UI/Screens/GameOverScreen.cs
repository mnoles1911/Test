using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

/// <summary>
/// Game over screen: title, kill count, level, Restart and Main Menu buttons.
/// </summary>
public class GameOverScreen : UIScreen
{
    public Action? OnRestart  { get; set; }
    public Action? OnMainMenu { get; set; }

    public int KillCount { get; set; }
    public int Level     { get; set; }

    private const int ScreenW = 1280;
    private const int ScreenH = 720;

    private const int PanelW = 360;
    private const int PanelH = 280;
    private const int ButtonW = 240;
    private const int ButtonH = 50;
    private const int ButtonSpacing = 14;

    private readonly Panel  _panel;
    private readonly Button _restartBtn;
    private readonly Button _mainMenuBtn;

    public GameOverScreen()
    {
        int panelX = (ScreenW - PanelW) / 2;
        int panelY = (ScreenH - PanelH) / 2;
        _panel = new Panel(new Rectangle(panelX, panelY, PanelW, PanelH));

        int btnX      = panelX + (PanelW - ButtonW) / 2;
        int totalBtnH = ButtonH * 2 + ButtonSpacing;
        int btnStartY = panelY + PanelH - totalBtnH - 20;

        _restartBtn = new Button("Restart",
            new Rectangle(btnX, btnStartY, ButtonW, ButtonH))
        {
            OnClick = () => OnRestart?.Invoke()
        };

        _mainMenuBtn = new Button("Main Menu",
            new Rectangle(btnX, btnStartY + ButtonH + ButtonSpacing, ButtonW, ButtonH))
        {
            OnClick = () => OnMainMenu?.Invoke()
        };
    }

    public override void Update(GameTime gameTime, MouseState mouse, KeyboardState keyboard)
    {
        _restartBtn.Update(gameTime, mouse);
        _mainMenuBtn.Update(gameTime, mouse);
    }

    public override void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font)
    {
        // Dark full-screen overlay
        spriteBatch.Draw(
            spriteManager.GetPixel(UITheme.Overlay),
            new Rectangle(0, 0, ScreenW, ScreenH),
            Color.White);

        // Panel
        _panel.Draw(spriteBatch, spriteManager, font);

        if (font != null)
        {
            // "GAME OVER" title
            var title    = "GAME OVER";
            var titleSz  = font.MeasureString(title);
            var titlePos = new Vector2(
                _panel.Bounds.X + (_panel.Bounds.Width - titleSz.X) / 2f,
                _panel.Bounds.Y + 16);
            spriteBatch.DrawString(font, title, titlePos, new Color(200, 50, 50));

            // Kill count
            var kills    = $"Kills: {KillCount}";
            var killsSz  = font.MeasureString(kills);
            var killsPos = new Vector2(
                _panel.Bounds.X + (_panel.Bounds.Width - killsSz.X) / 2f,
                _panel.Bounds.Y + 70);
            spriteBatch.DrawString(font, kills, killsPos, UITheme.TextPrimary);

            // Level
            var lvl    = $"Level: {Level}";
            var lvlSz  = font.MeasureString(lvl);
            var lvlPos = new Vector2(
                _panel.Bounds.X + (_panel.Bounds.Width - lvlSz.X) / 2f,
                _panel.Bounds.Y + 100);
            spriteBatch.DrawString(font, lvl, lvlPos, UITheme.TextPrimary);
        }

        // Buttons
        _restartBtn.Draw(spriteBatch, spriteManager, font);
        _mainMenuBtn.Draw(spriteBatch, spriteManager, font);
    }
}
