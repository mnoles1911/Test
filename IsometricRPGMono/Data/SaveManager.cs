using System.Text.Json;

namespace IsometricRPG;

public static class SaveManager
{
    private static string SaveDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "IsometricRPG");

    private static string SaveFile     => Path.Combine(SaveDir, "save.json");
    private static string SettingsFile => Path.Combine(SaveDir, "settings.json");

    public static bool SaveExists => File.Exists(SaveFile);

    // -------------------------------------------------------------------------
    // Game save

    public static void SaveGame(SaveData data)
    {
        Directory.CreateDirectory(SaveDir);
        string json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(SaveFile, json);
    }

    public static SaveData? LoadGame()
    {
        if (!File.Exists(SaveFile)) return null;
        try
        {
            string json = File.ReadAllText(SaveFile);
            return JsonSerializer.Deserialize<SaveData>(json);
        }
        catch { return null; }
    }

    public static void DeleteSave()
    {
        if (File.Exists(SaveFile)) File.Delete(SaveFile);
    }

    // -------------------------------------------------------------------------
    // Settings

    public static void SaveSettings(GameSettings settings)
    {
        Directory.CreateDirectory(SaveDir);
        string json = JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(SettingsFile, json);
    }

    public static GameSettings LoadSettings()
    {
        if (!File.Exists(SettingsFile)) return new GameSettings();
        try
        {
            string json = File.ReadAllText(SettingsFile);
            return JsonSerializer.Deserialize<GameSettings>(json) ?? new GameSettings();
        }
        catch { return new GameSettings(); }
    }
}
