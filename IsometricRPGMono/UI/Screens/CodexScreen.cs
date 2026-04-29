using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

/// <summary>
/// Codex screen: scrollable list of LoreEntry items from LoreRegistry (or sample entries).
/// Each entry shows title if unlocked, "???" if locked. Close button.
/// </summary>
public class CodexScreen : UIScreen
{
    public Action?      OnClose { get; set; }
    public GameContext? Context { get; set; }

    private List<LoreEntry> _entries;

    private const int ScreenW = 1280;
    private const int ScreenH = 720;
    private const int PanelW  = 700;
    private const int PanelH  = 520;
    private const int PanelX  = (ScreenW - PanelW) / 2;
    private const int PanelY  = (ScreenH - PanelH) / 2;

    // List area (left column)
    private const int ListX     = PanelX + 20;
    private const int ListY     = PanelY + 60;
    private const int ListW     = 240;
    private const int ListH     = PanelH - 100;
    private const int EntryH    = 36;
    private const int EntrySpacing = 4;

    // Detail area (right column)
    private const int DetailX = PanelX + ListW + 40;
    private const int DetailY = PanelY + 60;
    private const int DetailW = PanelW - ListW - 60;
    private const int DetailH = PanelH - 100;

    private readonly Panel  _panel;
    private readonly Button _closeBtn;

    private int  _scrollOffset  = 0;
    private int  _selectedIndex = -1;
    private bool _prevUp, _prevDown;

    private int MaxVisible => (ListH) / (EntryH + EntrySpacing);

    public CodexScreen(IEnumerable<LoreEntry>? entries = null)
    {
        _entries = entries?.ToList() ?? LoreEntry.SampleEntries.ToList();

        _panel = new Panel(new Rectangle(PanelX, PanelY, PanelW, PanelH));

        _closeBtn = new Button("Close",
            new Rectangle(PanelX + PanelW - 130, PanelY + PanelH - 60, 110, 40))
        {
            OnClick = () => OnClose?.Invoke()
        };
    }

    public void SetEntries(IEnumerable<LoreEntry> entries)
    {
        _entries = entries.ToList();
        _scrollOffset = 0;
        _selectedIndex = -1;
    }

    public override void Update(GameTime gameTime, MouseState mouse, KeyboardState keyboard)
    {
        _closeBtn.Update(gameTime, mouse);

        // Scroll with arrow keys
        bool upNow   = keyboard.IsKeyDown(Keys.Up);
        bool downNow = keyboard.IsKeyDown(Keys.Down);

        if (upNow && !_prevUp && _scrollOffset > 0)
            _scrollOffset--;
        if (downNow && !_prevDown && _scrollOffset < Math.Max(0, _entries.Count - MaxVisible))
            _scrollOffset++;

        _prevUp   = upNow;
        _prevDown = downNow;

        // Hit-test entry list on click
        if (mouse.LeftButton == ButtonState.Pressed)
        {
            for (int i = 0; i < MaxVisible; i++)
            {
                int entryIdx = _scrollOffset + i;
                if (entryIdx >= _entries.Count) break;

                int ex = ListX;
                int ey = ListY + i * (EntryH + EntrySpacing);
                if (mouse.X >= ex && mouse.X < ex + ListW &&
                    mouse.Y >= ey && mouse.Y < ey + EntryH)
                {
                    _selectedIndex = entryIdx;
                    break;
                }
            }
        }
    }

    public override void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font)
    {
        // Overlay
        spriteBatch.Draw(
            spriteManager.GetPixel(UITheme.Overlay),
            new Rectangle(0, 0, ScreenW, ScreenH),
            Color.White);

        // Panel
        _panel.Draw(spriteBatch, spriteManager, font);

        // Title
        if (font != null)
        {
            var titleSz  = font.MeasureString("CODEX OF LORE");
            var titlePos = new Vector2(
                PanelX + (PanelW - titleSz.X) / 2f,
                PanelY + 14);
            spriteBatch.DrawString(font, "CODEX OF LORE", titlePos, UITheme.Gold);
        }

        // Entry list
        DrawEntryList(spriteBatch, spriteManager, font);

        // Detail panel
        DrawDetailPanel(spriteBatch, spriteManager, font);

        // Scroll indicators
        if (font != null)
        {
            if (_scrollOffset > 0)
                spriteBatch.DrawString(font, "^ Up", new Vector2(ListX + ListW - 50, ListY - 20), UITheme.TextSecondary);
            if (_scrollOffset < _entries.Count - MaxVisible)
                spriteBatch.DrawString(font, "v Down", new Vector2(ListX + ListW - 60, ListY + ListH + 4), UITheme.TextSecondary);
        }

        _closeBtn.Draw(spriteBatch, spriteManager, font);
    }

    private void DrawEntryList(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font)
    {
        // List background
        spriteBatch.Draw(
            spriteManager.GetPixel(new Color(25, 20, 14)),
            new Rectangle(ListX - 4, ListY - 4, ListW + 8, ListH + 8),
            Color.White);

        for (int i = 0; i < MaxVisible; i++)
        {
            int entryIdx = _scrollOffset + i;
            if (entryIdx >= _entries.Count) break;

            var entry = _entries[entryIdx];
            int ex    = ListX;
            int ey    = ListY + i * (EntryH + EntrySpacing);
            var rect  = new Rectangle(ex, ey, ListW, EntryH);

            // Background highlight
            Color bg = entryIdx == _selectedIndex
                ? new Color(80, 65, 40)
                : new Color(40, 32, 22);
            spriteBatch.Draw(spriteManager.GetPixel(bg), rect, Color.White);
            DrawBorder(spriteBatch, spriteManager, rect,
                entryIdx == _selectedIndex ? UITheme.Gold : UITheme.PanelBorder, 1);

            // Entry text
            if (font != null)
            {
                string displayText = entry.IsUnlocked ? entry.Title : "???";
                Color  textColor   = entry.IsUnlocked ? UITheme.TextPrimary : UITheme.TextSecondary * 0.6f;

                // Category color dot
                Color catColor = CategoryColor(entry.Category);
                spriteBatch.Draw(spriteManager.GetPixel(catColor),
                    new Rectangle(ex + 4, ey + (EntryH - 8) / 2, 8, 8), Color.White);

                spriteBatch.DrawString(font, displayText,
                    new Vector2(ex + 16, ey + (EntryH - 16) / 2),
                    textColor, 0f, Vector2.Zero, 0.75f, SpriteEffects.None, 0f);
            }
        }
    }

    private void DrawDetailPanel(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font)
    {
        var detailRect = new Rectangle(DetailX, DetailY, DetailW, DetailH);
        spriteBatch.Draw(spriteManager.GetPixel(new Color(25, 20, 14)), detailRect, Color.White);
        DrawBorder(spriteBatch, spriteManager, detailRect, UITheme.PanelBorder, 1);

        if (font == null) return;

        if (_selectedIndex < 0 || _selectedIndex >= _entries.Count)
        {
            spriteBatch.DrawString(font, "Select an entry",
                new Vector2(DetailX + 12, DetailY + 12), UITheme.TextSecondary);
            return;
        }

        var entry = _entries[_selectedIndex];
        int tx    = DetailX + 12;
        int ty    = DetailY + 12;

        if (!entry.IsUnlocked)
        {
            spriteBatch.DrawString(font, "???",
                new Vector2(tx, ty), UITheme.TextSecondary);
            spriteBatch.DrawString(font, "This entry has not been unlocked yet.",
                new Vector2(tx, ty + 22), UITheme.TextSecondary * 0.7f,
                0f, Vector2.Zero, 0.8f, SpriteEffects.None, 0f);
            return;
        }

        // Title
        spriteBatch.DrawString(font, entry.Title,
            new Vector2(tx, ty), UITheme.Gold);

        // Category
        spriteBatch.DrawString(font, entry.Category.DisplayName(),
            new Vector2(tx, ty + 22), CategoryColor(entry.Category),
            0f, Vector2.Zero, 0.8f, SpriteEffects.None, 0f);

        // Body — word-wrap at ~40 chars
        var wrappedLines = WordWrap(entry.Body, 38);
        int lineY = ty + 48;
        foreach (var line in wrappedLines)
        {
            if (lineY + 16 > DetailY + DetailH - 8) break;
            spriteBatch.DrawString(font, line,
                new Vector2(tx, lineY), UITheme.TextPrimary,
                0f, Vector2.Zero, 0.8f, SpriteEffects.None, 0f);
            lineY += 18;
        }
    }

    private static List<string> WordWrap(string text, int maxChars)
    {
        var lines = new List<string>();
        var words = text.Split(' ');
        var current = "";
        foreach (var word in words)
        {
            var test = current.Length == 0 ? word : current + " " + word;
            if (test.Length > maxChars && current.Length > 0)
            {
                lines.Add(current);
                current = word;
            }
            else
            {
                current = test;
            }
        }
        if (current.Length > 0) lines.Add(current);
        return lines;
    }

    private static Color CategoryColor(LoreCategory cat)
    {
        return cat switch
        {
            LoreCategory.World      => new Color(100, 200, 100),
            LoreCategory.Bestiary   => new Color(200, 80,  80),
            LoreCategory.History    => new Color(200, 200, 80),
            LoreCategory.Characters => new Color(80,  150, 200),
            LoreCategory.Items      => new Color(200, 130, 50),
            LoreCategory.Locations  => new Color(150, 100, 200),
            _                       => UITheme.TextSecondary
        };
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
