using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;
using Microsoft.Xna.Framework.Input;

namespace IsometricRPG;

/// <summary>
/// Inventory screen: 5×4 backpack grid, 6-slot equipment panel, tooltip on hover, close button.
/// </summary>
public class InventoryScreen : UIScreen
{
    public Action? OnClose { get; set; }
    public Player? Player  { get; set; }

    private const int ScreenW = 1280;
    private const int ScreenH = 720;

    private const int PanelW = 740;
    private const int PanelH = 500;
    private const int PanelX = (ScreenW - PanelW) / 2;
    private const int PanelY = (ScreenH - PanelH) / 2;

    // Inventory grid: 5 cols × 4 rows = 20 slots
    private const int InvCols     = 5;
    private const int InvRows     = 4;
    private const int SlotSize    = 60;
    private const int SlotSpacing = 6;

    // Equipment slots: 6 (Head/Chest/Legs/Feet/MainHand/OffHand) in 2 cols × 3 rows
    private const int EqCols = 2;
    private const int EqRows = 3;

    private readonly Panel _panel;

    // Inventory grid top-left (within screen coords)
    private readonly int _invGridX;
    private readonly int _invGridY;

    // Equipment grid top-left
    private readonly int _eqGridX;
    private readonly int _eqGridY;

    private readonly Button _closeBtn;

    private int _hoveredInvSlot = -1;
    private int _hoveredEqSlot  = -1;

    private static readonly string[] EqSlotNames =
        { "Head", "Chest", "Legs", "Feet", "Main", "Off" };

    public InventoryScreen()
    {
        _panel = new Panel(new Rectangle(PanelX, PanelY, PanelW, PanelH));

        // Inventory grid starts at left side of panel
        _invGridX = PanelX + 30;
        _invGridY = PanelY + 60;

        // Equipment grid on the right
        int eqGridW = EqCols * (SlotSize + SlotSpacing) - SlotSpacing;
        _eqGridX = PanelX + PanelW - eqGridW - 30;
        _eqGridY = PanelY + 60;

        // Close button at bottom-right of panel
        _closeBtn = new Button("Close",
            new Rectangle(PanelX + PanelW - 130, PanelY + PanelH - 60, 110, 40))
        {
            OnClick = () => OnClose?.Invoke()
        };
    }

    public override void Update(GameTime gameTime, MouseState mouse, KeyboardState keyboard)
    {
        _closeBtn.Update(gameTime, mouse);

        // Track hovered slots for tooltip
        _hoveredInvSlot = HitTestGrid(mouse.X, mouse.Y, _invGridX, _invGridY, InvCols, InvRows);
        _hoveredEqSlot  = HitTestGrid(mouse.X, mouse.Y, _eqGridX,  _eqGridY,  EqCols,  EqRows);

        // Close on Escape or I
        if (keyboard.IsKeyDown(Keys.Escape) || keyboard.IsKeyDown(Keys.I))
        {
            // Handled by GameScene on key-down edge; no-op here to avoid double close
        }
    }

    public override void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font)
    {
        // Semi-transparent overlay
        spriteBatch.Draw(
            spriteManager.GetPixel(UITheme.Overlay),
            new Rectangle(0, 0, ScreenW, ScreenH),
            Color.White);

        // Panel
        _panel.Draw(spriteBatch, spriteManager, font);

        // Title
        if (font != null)
        {
            var titleSz  = font.MeasureString("INVENTORY");
            var titlePos = new Vector2(
                PanelX + (PanelW - titleSz.X) / 2f,
                PanelY + 14);
            spriteBatch.DrawString(font, "INVENTORY", titlePos, UITheme.Gold);

            // Section labels
            spriteBatch.DrawString(font, "Backpack", new Vector2(_invGridX, _invGridY - 22), UITheme.TextSecondary);
            spriteBatch.DrawString(font, "Equipment", new Vector2(_eqGridX, _eqGridY - 22), UITheme.TextSecondary);
        }

        // Draw inventory grid
        DrawGrid(spriteBatch, spriteManager, font,
            _invGridX, _invGridY, InvCols, InvRows,
            GetInventoryItems(), _hoveredInvSlot, false);

        // Draw equipment grid
        DrawGrid(spriteBatch, spriteManager, font,
            _eqGridX, _eqGridY, EqCols, EqRows,
            GetEquipmentItems(), _hoveredEqSlot, true);

        // Tooltip
        DrawTooltip(spriteBatch, spriteManager, font);

        // Close button
        _closeBtn.Draw(spriteBatch, spriteManager, font);
    }

    // ---- Helpers ----

    private void DrawGrid(
        SpriteBatch spriteBatch,
        SpriteManager spriteManager,
        SpriteFont? font,
        int gridX, int gridY,
        int cols, int rows,
        Item?[] items,
        int hoveredSlot,
        bool isEquipment)
    {

        for (int i = 0; i < cols * rows; i++)
        {
            int col = i % cols;
            int row = i / cols;
            int x   = gridX + col * (SlotSize + SlotSpacing);
            int y   = gridY + row * (SlotSize + SlotSpacing);
            var rect = new Rectangle(x, y, SlotSize, SlotSize);

            // Slot background
            Color slotBg = (i == hoveredSlot)
                ? new Color(70, 60, 40)
                : new Color(30, 25, 18);
            spriteBatch.Draw(spriteManager.GetPixel(slotBg), rect, Color.White);

            // Slot border
            DrawBorder(spriteBatch, spriteManager, rect,
                i == hoveredSlot ? UITheme.Gold : UITheme.PanelBorder, 1);

            // Equipment slot name label (small, top-left of empty slot)
            if (isEquipment && font != null && i < EqSlotNames.Length)
            {
                var item = (i < items.Length) ? items[i] : null;
                if (item == null)
                {
                    spriteBatch.DrawString(font, EqSlotNames[i],
                        new Vector2(x + 3, y + 3), UITheme.TextSecondary * 0.6f,
                        0f, Vector2.Zero, 0.7f, SpriteEffects.None, 0f);
                }
            }

            // Item color swatch
            if (i < items.Length && items[i] != null)
            {
                var item      = items[i]!;
                int swatchSize = SlotSize - 12;
                var swatchRect = new Rectangle(x + 6, y + 6, swatchSize, swatchSize);
                spriteBatch.Draw(spriteManager.GetPixel(item.Type.DisplayColor()), swatchRect, Color.White);
                DrawBorder(spriteBatch, spriteManager, swatchRect, item.Rarity.RarityColor(), 2);

                // Item name (tiny, clipped to slot width)
                if (font != null)
                {
                    spriteBatch.DrawString(font, item.Name,
                        new Vector2(x + 3, y + SlotSize - 16),
                        UITheme.TextPrimary, 0f, Vector2.Zero, 0.55f, SpriteEffects.None, 0f);
                }
            }
        }
    }

    private void DrawTooltip(SpriteBatch spriteBatch, SpriteManager spriteManager, SpriteFont? font)
    {
        if (font == null) return;

        Item? item = null;
        if (_hoveredInvSlot >= 0)
        {
            var items = GetInventoryItems();
            if (_hoveredInvSlot < items.Length)
                item = items[_hoveredInvSlot];
        }
        else if (_hoveredEqSlot >= 0)
        {
            var items = GetEquipmentItems();
            if (_hoveredEqSlot < items.Length)
                item = items[_hoveredEqSlot];
        }

        if (item == null) return;

        // Build tooltip text
        string[] lines = {
            item.Name,
            $"{item.Rarity.DisplayName()} {item.Type}",
            item.Description,
            item.Stats.Count > 0 ? string.Join(", ", item.Stats.Select(kv => $"{kv.Key}:{kv.Value}")) : ""
        };

        int tooltipW = 200;
        int tooltipH = lines.Length * 18 + 12;
        int tooltipX = Math.Min(1280 - tooltipW - 4, PanelX + PanelW + 4);
        int tooltipY = PanelY + 60;

        var tooltipRect = new Rectangle(tooltipX, tooltipY, tooltipW, tooltipH);
        spriteBatch.Draw(spriteManager.GetPixel(UITheme.Panel), tooltipRect, Color.White);
        DrawBorder(spriteBatch, spriteManager, tooltipRect, UITheme.Gold, 1);

        for (int li = 0; li < lines.Length; li++)
        {
            if (string.IsNullOrEmpty(lines[li])) continue;
            Color lineColor = li == 0 ? item.Rarity.RarityColor()
                            : li == 1 ? UITheme.TextSecondary
                                      : UITheme.TextPrimary;
            spriteBatch.DrawString(font, lines[li],
                new Vector2(tooltipX + 6, tooltipY + 6 + li * 18),
                lineColor, 0f, Vector2.Zero, 0.75f, SpriteEffects.None, 0f);
        }
    }

    private Item?[] GetInventoryItems()
    {
        if (Player == null) return new Item?[InvCols * InvRows];
        return Player.Inventory.ToArray();
    }

    private Item?[] GetEquipmentItems()
    {
        if (Player == null) return new Item?[EqCols * EqRows];
        return new Item?[]
        {
            Player.Equipment.Head.Item,
            Player.Equipment.Chest.Item,
            Player.Equipment.Legs.Item,
            Player.Equipment.Feet.Item,
            Player.Equipment.MainHand.Item,
            Player.Equipment.OffHand.Item
        };
    }

    private int HitTestGrid(int mx, int my, int gridX, int gridY, int cols, int rows)
    {
        for (int i = 0; i < cols * rows; i++)
        {
            int col = i % cols;
            int row = i / cols;
            int x   = gridX + col * (SlotSize + SlotSpacing);
            int y   = gridY + row * (SlotSize + SlotSpacing);
            if (mx >= x && mx < x + SlotSize && my >= y && my < y + SlotSize)
                return i;
        }
        return -1;
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
