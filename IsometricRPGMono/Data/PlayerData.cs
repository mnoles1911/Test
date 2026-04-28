using System.Text.Json.Serialization;

namespace IsometricRPG;

public class PlayerData
{
    [JsonInclude]
    public string PlayerName    { get; set; } = "Hero";

    [JsonInclude]
    public int Level            { get; set; } = 1;

    [JsonInclude]
    public int Experience       { get; set; } = 0;

    [JsonInclude]
    public int Health           { get; set; } = Constants.PlayerMaxHealth;

    [JsonInclude]
    public int MaxHealth        { get; set; } = Constants.PlayerMaxHealth;

    [JsonInclude]
    public int Gold             { get; set; } = 0;

    [JsonInclude]
    public List<Item> Inventory { get; set; } = new List<Item>();

    [JsonInclude]
    public EquipmentSet Equipment { get; set; } = new EquipmentSet();

    [JsonInclude]
    public int EnemiesKilled    { get; set; } = 0;

    [JsonInclude]
    public int ChunksExplored   { get; set; } = 0;

    [JsonInclude]
    public int ItemsCollected   { get; set; } = 0;

    [JsonInclude]
    public bool BossDefeated    { get; set; } = false;

    [JsonInclude]
    public List<string> UnlockedLoreIds { get; set; } = new List<string>();

    [JsonInclude]
    public List<string> Flags   { get; set; } = new List<string>();

    // Level formula: XP needed to reach the NEXT level from current level
    public int ExperienceToNextLevel => (int)(100 * Math.Pow(1.5, Level - 1));

    public bool IsAlive => Health > 0;

    public void AddExperience(int amount)
    {
        Experience += amount;
        while (Experience >= ExperienceToNextLevel)
        {
            Experience -= ExperienceToNextLevel;
            Level++;
            OnLevelUp();
        }
    }

    private void OnLevelUp()
    {
        // Increase max health by 10 each level
        MaxHealth += 10;
        Health = MaxHealth;
    }

    public void TakeDamage(int amount)
    {
        Health = Math.Max(0, Health - amount);
    }

    public void Heal(int amount)
    {
        Health = Math.Min(MaxHealth, Health + amount);
    }

    public bool HasFlag(string flag) => Flags.Contains(flag);

    public void SetFlag(string flag)
    {
        if (!Flags.Contains(flag))
            Flags.Add(flag);
    }

    public GameContext ToGameContext()
    {
        return new GameContext
        {
            PlayerLevel    = Level,
            ChunksExplored = ChunksExplored,
            EnemiesKilled  = EnemiesKilled,
            ItemsCollected = ItemsCollected,
            BossDefeated   = BossDefeated,
            Flags          = new List<string>(Flags)
        };
    }
}
