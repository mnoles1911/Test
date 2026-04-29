using Microsoft.Xna.Framework;
using Microsoft.Xna.Framework.Graphics;

namespace IsometricRPG;

public class WorldItem
{
    public Item        ItemData    { get; }
    public Vector2     WorldPosition { get; set; }
    public double      HoverTimer  { get; private set; }
    public bool        IsCollected { get; private set; }

    public WorldItem(Item itemData, Vector2 worldPosition)
    {
        ItemData      = itemData;
        WorldPosition = worldPosition;
    }

    public void Update(double deltaTime)
    {
        HoverTimer += deltaTime;
    }

    /// Apply this item's effect to the player.
    public void ApplyEffect(Player player)
    {
        switch (ItemData.Type)
        {
            case ItemType.HealthPotion:
                player.Health = Math.Min(player.MaxHealth, player.Health + 30);
                break;

            case ItemType.ManaPotion:
                player.ApplyBuff(BuffType.FireRate, 1.5f, 8.0);
                break;

            case ItemType.Antidote:
                player.Health = Math.Min(player.MaxHealth, player.Health + 15);
                break;

            case ItemType.Food:
                player.Health = Math.Min(player.MaxHealth, player.Health + 10);
                break;

            // Speed-boosting items
            case ItemType.Boots:
                player.ApplyBuff(BuffType.Speed, 1.5f, 10.0);
                break;

            // Armor items → equip slot (best-effort: add to equipment chest/head/legs/feet)
            case ItemType.Helmet:
                player.Equipment.Head.Equip(ItemData);
                break;
            case ItemType.ChestArmor:
                player.Equipment.Chest.Equip(ItemData);
                break;
            case ItemType.Leggings:
                player.Equipment.Legs.Equip(ItemData);
                break;
            case ItemType.Shield:
                player.Equipment.OffHand.Equip(ItemData);
                break;

            // Weapons
            case ItemType.Sword:
            case ItemType.Bow:
            case ItemType.Staff:
            case ItemType.Dagger:
            case ItemType.Axe:
                player.AddToInventory(ItemData);
                break;

            // Treasure / materials
            case ItemType.Gold:
            case ItemType.Gem:
            case ItemType.Artifact:
            case ItemType.QuestScroll:
            case ItemType.AncientKey:
            case ItemType.CrystalShard:
            case ItemType.Wood:
            case ItemType.Stone:
            case ItemType.Iron:
            case ItemType.Leather:
            case ItemType.Cloth:
                player.AddToInventory(ItemData);
                break;
        }

        IsCollected = true;
    }

    public void Draw(SpriteBatch spriteBatch, SpriteManager spriteManager, Vector2 cameraPos)
    {
        if (IsCollected) return;

        // Sin-wave hover: offsetY oscillates by ±4 pixels
        float offsetY = (float)Math.Sin(HoverTimer * Math.PI * 2.0) * 4f;

        var screenPos = IsometricMath.WorldToScreen(WorldPosition) - cameraPos;
        screenPos.Y  += offsetY;

        var color = ItemData.Type.DisplayColor();
        const int size = 10;
        var tex = spriteManager.GetRect(size, size, color);
        spriteBatch.Draw(tex,
            new Vector2(screenPos.X - size / 2f, screenPos.Y - size / 2f),
            Color.White);
    }
}
