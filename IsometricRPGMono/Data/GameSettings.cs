using System.Text.Json.Serialization;

namespace IsometricRPG;

public class GameSettings
{
    [JsonInclude] public float MasterVolume  { get; set; } = 1f;
    [JsonInclude] public float MusicVolume   { get; set; } = 0.5f;
    [JsonInclude] public float SfxVolume     { get; set; } = 0.8f;
    [JsonInclude] public bool  MusicEnabled  { get; set; } = true;
    [JsonInclude] public bool  SfxEnabled    { get; set; } = true;
}
