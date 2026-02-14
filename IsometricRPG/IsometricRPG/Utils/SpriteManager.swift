import SpriteKit

/// Centralized sprite loading and caching system
/// Loads sprites from asset catalog with fallback to procedural generation
class SpriteManager {

    // MARK: - Singleton

    static let shared = SpriteManager()
    private init() {}

    // MARK: - Texture Cache

    private var textureCache: [String: SKTexture] = [:]

    // MARK: - Public Methods

    /// Get sprite texture for an item type
    func getItemSprite(_ itemType: ItemType) -> SKTexture {
        let spriteName = itemSpriteName(for: itemType)
        return getTexture(named: spriteName, fallback: {
            // Fallback: create procedural circle with item color
            return createCircleTexture(color: itemType.color, size: CGSize(width: 32, height: 32))
        })
    }

    /// Get sprite texture for a UI icon
    func getIconSprite(_ iconName: String) -> SKTexture {
        let spriteName = "icon_\(iconName)"
        return getTexture(named: spriteName, fallback: {
            // Fallback: create simple colored square
            return createSquareTexture(color: UITheme.gold, size: CGSize(width: 24, height: 24))
        })
    }

    /// Get sprite texture for an equipment slot
    func getEquipmentSprite(_ slot: Equipment.EquipmentSlot) -> SKTexture {
        let spriteName = "equipment_\(slot.rawValue)"
        return getTexture(named: spriteName, fallback: {
            // Fallback: create square placeholder
            return createSquareTexture(color: UITheme.parchmentDark, size: CGSize(width: 48, height: 48))
        })
    }

    /// Get sprite texture for an entity
    func getEntitySprite(_ entityType: String) -> SKTexture {
        return getTexture(named: entityType, fallback: {
            // Fallback: create colored rectangle
            let color: UIColor
            switch entityType {
            case "player_idle": color = UIColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
            case "enemy_basic": color = UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1)
            case "bullet_basic": color = UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1)
            default: color = .gray
            }
            let size = entitySize(for: entityType)
            return createSquareTexture(color: color, size: size)
        })
    }

    /// Get shadow texture for entities
    func getShadowSprite(width: CGFloat) -> SKTexture {
        let cacheName = "shadow_\(Int(width))"
        return getTexture(named: cacheName, fallback: {
            return createShadowTexture(width: width)
        })
    }

    /// Preload frequently used sprites
    func preloadCommonSprites() {
        // Preload all item sprites
        for itemType in ItemType.allCases {
            _ = getItemSprite(itemType)
        }

        // Preload common icons
        let commonIcons = ["heart", "xp_star", "skull", "pause", "attack", "defense", "speed"]
        for icon in commonIcons {
            _ = getIconSprite(icon)
        }

        // Preload entity sprites
        _ = getEntitySprite("player_idle")
        _ = getEntitySprite("enemy_basic")
        _ = getEntitySprite("bullet_basic")

        print("✅ Preloaded \(textureCache.count) sprites")
    }

    /// Clear texture cache (for memory management)
    func clearCache() {
        textureCache.removeAll()
    }

    // MARK: - Private Helpers

    /// Get texture from cache or load/generate it
    private func getTexture(named name: String, fallback: () -> SKTexture) -> SKTexture {
        // Check cache first
        if let cached = textureCache[name] {
            return cached
        }

        // Try to load from asset catalog
        let texture: SKTexture
        if assetExists(named: name) {
            texture = SKTexture(imageNamed: name)
            texture.filteringMode = .nearest  // Pixel art style
        } else {
            // Use fallback procedural generation
            texture = fallback()
        }

        // Cache and return
        textureCache[name] = texture
        return texture
    }

    /// Check if an asset exists in the asset catalog
    private func assetExists(named name: String) -> Bool {
        // Try to load UIImage to check existence
        return UIImage(named: name) != nil
    }

    /// Get sprite name for item type
    private func itemSpriteName(for itemType: ItemType) -> String {
        switch itemType {
        case .healthPotion:      return "item_health_potion"
        case .healthPotionLarge: return "item_health_potion_large"
        case .speedBoost:        return "item_speed_boost"
        case .damageBoost:       return "item_damage_boost"
        case .shieldOrb:         return "item_shield_orb"
        case .ammoCache:         return "item_ammo_cache"
        case .xpMultiplier:      return "item_xp_multiplier"
        case .armorShard:        return "item_armor_shard"
        case .dungeonKey:        return "item_dungeon_key"
        case .rareTreasure:      return "item_rare_treasure"
        }
    }

    /// Get entity size for fallback generation
    private func entitySize(for entityType: String) -> CGSize {
        switch entityType {
        case "player_idle": return CGSize(width: 32, height: 40)
        case "enemy_basic": return CGSize(width: 28, height: 36)
        case "bullet_basic": return CGSize(width: 8, height: 8)
        case "player_shadow": return CGSize(width: 24, height: 12)
        case "enemy_shadow": return CGSize(width: 20, height: 10)
        default: return CGSize(width: 32, height: 32)
        }
    }

    // MARK: - Procedural Texture Generation

    /// Create a circle texture (fallback for items)
    private func createCircleTexture(color: UIColor, size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            context.cgContext.setFillColor(color.cgColor)

            let radius = min(size.width, size.height) / 2 - 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            context.cgContext.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.cgContext.fillPath()

            // Add highlight
            context.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.3).cgColor)
            context.cgContext.addEllipse(in: CGRect(
                x: center.x - radius * 0.4,
                y: center.y - radius * 0.6,
                width: radius * 0.6,
                height: radius * 0.6
            ))
            context.cgContext.fillPath()
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }

    /// Create a square texture (fallback for icons/equipment)
    private func createSquareTexture(color: UIColor, size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            // Fill with color
            context.cgContext.setFillColor(color.cgColor)
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.fillPath()

            // Border
            context.cgContext.setStrokeColor(UITheme.gold.cgColor)
            context.cgContext.setLineWidth(1)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.strokePath()
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }

    /// Create shadow texture
    private func createShadowTexture(width: CGFloat) -> SKTexture {
        let size = CGSize(width: width, height: width / 2.5)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.3).cgColor)
            context.cgContext.addEllipse(in: CGRect(origin: .zero, size: size))
            context.cgContext.fillPath()
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear  // Smooth shadows
        return texture
    }
}
