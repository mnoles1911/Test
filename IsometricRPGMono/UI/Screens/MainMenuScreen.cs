using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

/// <summary>
/// Main menu screen: title, New Game, Continue (optional), and Quit buttons.
/// </summary>
public class MainMenuScreen : UIScreen
{
    public Action? OnNewGame  { get; set; }
    public Action? OnContinue { get; set; }
    public Action? OnQuit     { get; set; }

    public bool ContinueEnabled { get; set; } = false;

    private const int ScreenW = 1280;
    private const int ScreenH = 720;

    private const int ButtonW = 240;
    private const int ButtonH = 50;
    private const int ButtonSpacing = 14;

    private readonly Button _newGameBtn;
    private readonly Button _continueBtn;
    private readonly Button _quitBtn;

    // Title area
    private readonly Panel _titlePanel;
    private readonly Label _titleLabel;
    private readonly Label _subtitleLabel;

    public MainMenuScreen()
    {
        // ---- Title panel ----
        int titlePanelW = 400;
        int titlePanelH = 80;
        int titlePanelX = (ScreenW - titlePanelW) / 2;
        int titlePanelY = ScreenH / 2 - 200;
        _titlePanel = new Panel(new Rectangle(titlePanelX, titlePanelY, titlePanelW, titlePanelH));

        _titleLabel = new Label("HAMMERFELL",
            new Rectangle(titlePanelX, titlePanelY + 12, titlePanelW, 30))
        {
            TextColor = UITheme.Gold
        };

        _subtitleLabel = new Label("The Elder Province",
            new Rectangle(titlePanelX, titlePanelY + 46, titlePanelW, 20))
        {
            TextColor = UITheme.TextSecondary
        };

        // ---- Buttons (centered horizontally, stacked vertically) ----
        int totalButtons = 3;
        int totalH = totalButtons * ButtonH + (totalButtons - 1) * ButtonSpacing;
        int startY = (ScreenH - totalH) / 2 + 20;
        int btnX = (ScreenW - ButtonW) / 2;

        _newGameBtn = new Button("New Game",
            new Rectangle(btnX, startY, ButtonW, ButtonH))
        {
            OnClick = () => OnNewGame?.Invoke()
        };

        _continueBtn = new Button("Continue",
            new Rectangle(btnX, startY + ButtonH + ButtonSpacing, ButtonW, ButtonH))
        {
            OnClick = () => OnContinue?.Invoke()
        };

        _quitBtn = new Button("Quit",
            new Rectangle(btnX, startY + (ButtonH + ButtonSpacing) * 2, ButtonW, ButtonH))
        {
            OnClick = () => OnQuit?.Invoke()
        };
    }

    public override void Update(GameTime gameTime, MouseState mouse, KeyboardState keyboard)
    {
        _newGameBtn.Update(gameTime, mouse);

        // Only allow Continue click if enabled
        if (ContinueEnabled)
            _continueBtn.Update(gameTime, mouse);

        _quitBtn.Update(gameTime, mouse);
    }

    public override void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font)
    {
        // Full-screen background
        spriteBatch.Draw(
            spriteManager.GetPixel(UITheme.Background),
            new Rectangle(0, 0, ScreenW, ScreenH),
            Color.White);

        // Title panel
        _titlePanel.Draw(spriteBatch, spriteManager, font);

        // Title text — centered within panel
        if (font != null)
        {
            var titleSize = font.MeasureString("HAMMERFELL");
            var titlePos  = new Vector2(
                _titlePanel.Bounds.X + (_titlePanel.Bounds.Width - titleSize.X) / 2f,
                _titlePanel.Bounds.Y + 12);
            spriteBatch.DrawString(font, "HAMMERFELL", titlePos, UITheme.Gold);

            var subSize = font.MeasureString("The Elder Province");
            var subPos  = new Vector2(
                _titlePanel.Bounds.X + (_titlePanel.Bounds.Width - subSize.X) / 2f,
                _titlePanel.Bounds.Y + 46);
            spriteBatch.DrawString(font, "The Elder Province", subPos, UITheme.TextSecondary);
        }

        // Buttons
        _newGameBtn.Draw(spriteBatch, spriteManager, font);

        // Continue: draw grayed out if disabled
        if (ContinueEnabled)
        {
            _continueBtn.Draw(spriteBatch, spriteManager, font);
        }
        else
        {
            // Draw a grayed-out version
            spriteBatch.Draw(
                spriteManager.GetPixel(new Color(40, 35, 30)),
                _continueBtn.Bounds,
                Color.White);
            DrawBorder(spriteBatch, spriteManager, _continueBtn.Bounds, new Color(70, 60, 50), 2);
            if (font != null)
            {
                var sz  = font.MeasureString("Continue");
                var pos = new Vector2(
                    _continueBtn.Bounds.X + (_continueBtn.Bounds.Width  - sz.X) / 2f,
                    _continueBtn.Bounds.Y + (_continueBtn.Bounds.Height - sz.Y) / 2f);
                spriteBatch.DrawString(font, "Continue", pos, UITheme.TextSecondary * 0.5f);
            }
        }

        _quitBtn.Draw(spriteBatch, spriteManager, font);
    }

    private static void DrawBorder(SpriteBatch sb, SpriteManager sm, Rectangle rect, Color color, int t)
    {
        var tex = sm.GetPixel(color);
        sb.Draw(tex, new Rectangle(rect.X, rect.Y, rect.Width, t), Color.White);
        sb.Draw(tex, new Rectangle(rect.X, rect.Bottom - t, rect.Width, t), Color.White);
        sb.Draw(tex, new Rectangle(rect.X, rect.Y, t, rect.Height), Color.White);
        sb.Draw(tex, new Rectangle(rect.Right - t, rect.Y, t, rect.Height), Color.White);
    }
}
