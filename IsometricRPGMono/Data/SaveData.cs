using System.Text.Json.Serialization;

namespace IsometricRPG;

public class SaveData
{
    [JsonInclude] public PlayerData   PlayerStats   { get; set; } = new PlayerData();
    [JsonInclude] public List<Item?>  Inventory     { get; set; } = new List<Item?>();
    [JsonInclude] public EquipmentSet Equipment     { get; set; } = new EquipmentSet();
    [JsonInclude] public GameContext  Context       { get; set; } = new GameContext();
    [JsonInclude] public int          KillCount     { get; set; }
    [JsonInclude] public float        PlayerWorldX  { get; set; }
    [JsonInclude] public float        PlayerWorldY  { get; set; }
}
