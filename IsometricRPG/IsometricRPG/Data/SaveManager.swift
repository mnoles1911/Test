import Foundation

/// Save/load system for player data using UserDefaults
class SaveManager {
    // MARK: - Singleton

    static let shared = SaveManager()

    private init() {}

    // MARK: - Keys

    private enum Keys {
        static let playerData = "playerData"
        static let inventory = "inventory"
        static let equipment = "equipment"
        static let settings = "settings"
    }

    // MARK: - Player Data

    /// Save player data to UserDefaults
    func savePlayerData(_ data: PlayerData) {
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(data)
            UserDefaults.standard.set(encoded, forKey: Keys.playerData)
            print("[SaveManager] Player data saved successfully")
        } catch {
            print("[SaveManager] Failed to save player data: \(error)")
        }
    }

    /// Load player data from UserDefaults
    func loadPlayerData() -> PlayerData? {
        guard let data = UserDefaults.standard.data(forKey: Keys.playerData) else {
            print("[SaveManager] No saved player data found")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let playerData = try decoder.decode(PlayerData.self, from: data)
            print("[SaveManager] Player data loaded successfully")
            return playerData
        } catch {
            print("[SaveManager] Failed to load player data: \(error)")
            return nil
        }
    }

    /// Delete saved player data (for new game)
    func deletePlayerData() {
        UserDefaults.standard.removeObject(forKey: Keys.playerData)
        print("[SaveManager] Player data deleted")
    }

    // MARK: - Inventory

    /// Save inventory
    func saveInventory(_ inventory: [Item]) {
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(inventory)
            UserDefaults.standard.set(encoded, forKey: Keys.inventory)
            print("[SaveManager] Inventory saved successfully")
        } catch {
            print("[SaveManager] Failed to save inventory: \(error)")
        }
    }

    /// Load inventory
    func loadInventory() -> [Item]? {
        guard let data = UserDefaults.standard.data(forKey: Keys.inventory) else {
            print("[SaveManager] No saved inventory found")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let inventory = try decoder.decode([Item].self, from: data)
            print("[SaveManager] Inventory loaded successfully")
            return inventory
        } catch {
            print("[SaveManager] Failed to load inventory: \(error)")
            return nil
        }
    }

    // MARK: - Equipment

    /// Save equipment
    func saveEquipment(_ equipment: Equipment) {
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(equipment)
            UserDefaults.standard.set(encoded, forKey: Keys.equipment)
            print("[SaveManager] Equipment saved successfully")
        } catch {
            print("[SaveManager] Failed to save equipment: \(error)")
        }
    }

    /// Load equipment
    func loadEquipment() -> Equipment? {
        guard let data = UserDefaults.standard.data(forKey: Keys.equipment) else {
            print("[SaveManager] No saved equipment found")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let equipment = try decoder.decode(Equipment.self, from: data)
            print("[SaveManager] Equipment loaded successfully")
            return equipment
        } catch {
            print("[SaveManager] Failed to load equipment: \(error)")
            return nil
        }
    }

    // MARK: - Settings

    struct GameSettings: Codable {
        var soundVolume: Float = 1.0
        var musicVolume: Float = 0.7
        var joystickSize: String = "normal" // "small" or "large"
        var showFPS: Bool = true
        var showMinimap: Bool = true
    }

    /// Save game settings
    func saveSettings(_ settings: GameSettings) {
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(settings)
            UserDefaults.standard.set(encoded, forKey: Keys.settings)
            print("[SaveManager] Settings saved successfully")
        } catch {
            print("[SaveManager] Failed to save settings: \(error)")
        }
    }

    /// Load game settings
    func loadSettings() -> GameSettings {
        guard let data = UserDefaults.standard.data(forKey: Keys.settings) else {
            print("[SaveManager] No saved settings found, using defaults")
            return GameSettings()
        }

        do {
            let decoder = JSONDecoder()
            let settings = try decoder.decode(GameSettings.self, from: data)
            print("[SaveManager] Settings loaded successfully")
            return settings
        } catch {
            print("[SaveManager] Failed to load settings: \(error)")
            return GameSettings()
        }
    }

    // MARK: - Complete Save/Load

    /// Save all game data at once
    func saveAll(playerData: PlayerData, inventory: [Item], equipment: Equipment) {
        savePlayerData(playerData)
        saveInventory(inventory)
        saveEquipment(equipment)
    }

    /// Check if save data exists
    func hasSaveData() -> Bool {
        return UserDefaults.standard.data(forKey: Keys.playerData) != nil
    }

    /// Delete all save data (new game)
    func deleteAllData() {
        UserDefaults.standard.removeObject(forKey: Keys.playerData)
        UserDefaults.standard.removeObject(forKey: Keys.inventory)
        UserDefaults.standard.removeObject(forKey: Keys.equipment)
        print("[SaveManager] All save data deleted")
    }
}
