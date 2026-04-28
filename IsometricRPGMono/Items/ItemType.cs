using Microsoft.Xna.Framework;

namespace IsometricRPG;

public enum ItemCategory
{
    Weapon,
    Armor,
    Consumable,
    Quest,
    Treasure,
    Material
}

public enum ItemType
{
    // Weapons
    Sword,
    Bow,
    Staff,
    Dagger,
    Axe,
    // Armor
    Helmet,
    ChestArmor,
    Leggings,
    Boots,
    Shield,
    // Consumables
    HealthPotion,
    ManaPotion,
    Antidote,
    Food,
    // Quest items
    QuestScroll,
    AncientKey,
    CrystalShard,
    // Treasure
    Gold,
    Gem,
    Artifact,
    // Materials
    Wood,
    Stone,
    Iron,
    Leather,
    Cloth
}

public static class ItemTypeExtensions
{
    public static ItemCategory Category(this ItemType itemType)
    {
        return itemType switch
        {
            ItemType.Sword or ItemType.Bow or ItemType.Staff
                or ItemType.Dagger or ItemType.Axe
                => ItemCategory.Weapon,

            ItemType.Helmet or ItemType.ChestArmor or ItemType.Leggings
                or ItemType.Boots or ItemType.Shield
                => ItemCategory.Armor,

            ItemType.HealthPotion or ItemType.ManaPotion or ItemType.Antidote
                or ItemType.Food
                => ItemCategory.Consumable,

            ItemType.QuestScroll or ItemType.AncientKey or ItemType.CrystalShard
                => ItemCategory.Quest,

            ItemType.Gold or ItemType.Gem or ItemType.Artifact
                => ItemCategory.Treasure,

            ItemType.Wood or ItemType.Stone or ItemType.Iron
                or ItemType.Leather or ItemType.Cloth
                => ItemCategory.Material,

            _ => ItemCategory.Material
        };
    }

    public static Color DisplayColor(this ItemType itemType)
    {
        return itemType.Category() switch
        {
            ItemCategory.Weapon     => new Color(204, 51,  51),   // ~(0.8, 0.2, 0.2)
            ItemCategory.Armor      => new Color(51,  102, 204),  // ~(0.2, 0.4, 0.8)
            ItemCategory.Consumable => new Color(51,  204, 51),   // ~(0.2, 0.8, 0.2)
            ItemCategory.Quest      => new Color(204, 153, 51),   // ~(0.8, 0.6, 0.2)
            ItemCategory.Treasure   => new Color(255, 215, 0),    // gold
            ItemCategory.Material   => new Color(153, 153, 153),  // ~(0.6, 0.6, 0.6)
            _ => Color.White
        };
    }
}
