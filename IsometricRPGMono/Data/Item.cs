using Microsoft.Xna.Framework;
using System.Text.Json.Serialization;

namespace IsometricRPG;

public enum Rarity
{
    Common,
    Uncommon,
    Rare,
    Legendary
}

public static class RarityExtensions
{
    public static Color RarityColor(this Rarity rarity)
    {
        return rarity switch
        {
            Rarity.Common    => Color.Gray,
            Rarity.Uncommon  => Color.Green,
            Rarity.Rare      => Color.Blue,
            Rarity.Legendary => new Color(255, 215, 0), // gold
            _                => Color.Gray
        };
    }

    public static string DisplayName(this Rarity rarity)
    {
        return rarity switch
        {
            Rarity.Common    => "Common",
            Rarity.Uncommon  => "Uncommon",
            Rarity.Rare      => "Rare",
            Rarity.Legendary => "Legendary",
            _                => "Common"
        };
    }
}

public class Item
{
    [JsonInclude]
    public string Id          { get; set; } = string.Empty;

    [JsonInclude]
    public string Name        { get; set; } = string.Empty;

    [JsonInclude]
    public string Description { get; set; } = string.Empty;

    [JsonInclude]
    public ItemType Type      { get; set; }

    [JsonInclude]
    public Rarity Rarity      { get; set; }

    [JsonInclude]
    public int Value          { get; set; }

    [JsonInclude]
    public float Weight       { get; set; }

    [JsonInclude]
    public bool IsStackable   { get; set; }

    [JsonInclude]
    public int StackSize      { get; set; } = 1;

    [JsonInclude]
    public int MaxStackSize   { get; set; } = 1;

    [JsonInclude]
    public Dictionary<string, int> Stats { get; set; } = new Dictionary<string, int>();

    public Item() { }

    public Item(
        string id,
        string name,
        string description,
        ItemType type,
        Rarity rarity,
        int value,
        float weight,
        bool isStackable = false,
        int maxStackSize = 1,
        Dictionary<string, int>? stats = null)
    {
        Id           = id;
        Name         = name;
        Description  = description;
        Type         = type;
        Rarity       = rarity;
        Value        = value;
        Weight       = weight;
        IsStackable  = isStackable;
        StackSize    = 1;
        MaxStackSize = maxStackSize;
        Stats        = stats ?? new Dictionary<string, int>();
    }

    public Color DisplayColor => Rarity.RarityColor();

    public bool CanStack(Item other) =>
        IsStackable && other.IsStackable && Id == other.Id && StackSize < MaxStackSize;

    public Item Clone()
    {
        return new Item
        {
            Id           = Id,
            Name         = Name,
            Description  = Description,
            Type         = Type,
            Rarity       = Rarity,
            Value        = Value,
            Weight       = Weight,
            IsStackable  = IsStackable,
            StackSize    = StackSize,
            MaxStackSize = MaxStackSize,
            Stats        = new Dictionary<string, int>(Stats)
        };
    }
}
