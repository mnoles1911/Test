using System.Text.Json.Serialization;

namespace IsometricRPG;

public enum EquipmentSlot
{
    Head,
    Chest,
    Legs,
    Feet,
    MainHand,
    OffHand
}

public class Equipment
{
    [JsonInclude]
    public EquipmentSlot Slot  { get; set; }

    [JsonInclude]
    public Item? Item           { get; set; }

    public Equipment(EquipmentSlot slot)
    {
        Slot = slot;
        Item = null;
    }

    [JsonConstructor]
    public Equipment() { }

    public bool IsEmpty => Item == null;

    public void Equip(Item item)   { Item = item; }
    public Item? Unequip()
    {
        var prev = Item;
        Item = null;
        return prev;
    }

    /// <summary>
    /// Sum of all stat bonuses provided by the equipped item.
    /// Returns 0 if nothing is equipped or the stat is not present.
    /// </summary>
    public int GetStat(string statName)
    {
        if (Item == null) return 0;
        return Item.Stats.TryGetValue(statName, out int val) ? val : 0;
    }
}

public class EquipmentSet
{
    [JsonInclude]
    public Equipment Head      { get; set; } = new Equipment(EquipmentSlot.Head);

    [JsonInclude]
    public Equipment Chest     { get; set; } = new Equipment(EquipmentSlot.Chest);

    [JsonInclude]
    public Equipment Legs      { get; set; } = new Equipment(EquipmentSlot.Legs);

    [JsonInclude]
    public Equipment Feet      { get; set; } = new Equipment(EquipmentSlot.Feet);

    [JsonInclude]
    public Equipment MainHand  { get; set; } = new Equipment(EquipmentSlot.MainHand);

    [JsonInclude]
    public Equipment OffHand   { get; set; } = new Equipment(EquipmentSlot.OffHand);

    public Equipment GetSlot(EquipmentSlot slot)
    {
        return slot switch
        {
            EquipmentSlot.Head      => Head,
            EquipmentSlot.Chest     => Chest,
            EquipmentSlot.Legs      => Legs,
            EquipmentSlot.Feet      => Feet,
            EquipmentSlot.MainHand  => MainHand,
            EquipmentSlot.OffHand   => OffHand,
            _ => throw new ArgumentOutOfRangeException(nameof(slot))
        };
    }

    /// <summary>Total stat bonus across all equipped items.</summary>
    public int TotalStat(string statName)
    {
        return Head.GetStat(statName)
             + Chest.GetStat(statName)
             + Legs.GetStat(statName)
             + Feet.GetStat(statName)
             + MainHand.GetStat(statName)
             + OffHand.GetStat(statName);
    }
}
