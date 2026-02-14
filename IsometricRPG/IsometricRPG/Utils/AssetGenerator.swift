import UIKit
import SpriteKit

/// Utility for programmatically generating placeholder sprite assets
/// Generates PNG sprites using Core Graphics for items, icons, and UI elements
class AssetGenerator {

    // MARK: - Asset Generation

    /// Generate all sprite assets and save to specified directory
    static func generateAllAssets(to directory: URL) throws {
        let fileManager = FileManager.default

        // Create directories
        let itemsDir = directory.appendingPathComponent("Items")
        let uiDir = directory.appendingPathComponent("UI")
        let entitiesDir = directory.appendingPathComponent("Entities")

        try fileManager.createDirectory(at: itemsDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: uiDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: entitiesDir, withIntermediateDirectories: true)

        // Generate item sprites
        try generateItemSprites(to: itemsDir)

        // Generate UI icon sprites
        try generateUIIcons(to: uiDir)

        // Generate entity sprites
        try generateEntitySprites(to: entitiesDir)

        print("✅ All sprites generated successfully at: \(directory.path)")
    }

    // MARK: - Item Sprites

    private static func generateItemSprites(to directory: URL) throws {
        let size = CGSize(width: 32, height: 32)

        // Health Potion - Red potion bottle
        try generateSprite(
            name: "item_health_potion",
            size: size,
            directory: directory
        ) { context in
            drawPotion(in: context, color: UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1))
        }

        // Large Health Potion - Larger red potion
        try generateSprite(
            name: "item_health_potion_large",
            size: size,
            directory: directory
        ) { context in
            drawPotion(in: context, color: UIColor(red: 1.0, green: 0.0, blue: 0.3, alpha: 1), scale: 1.2)
        }

        // Speed Boost - Cyan wing/swirl
        try generateSprite(
            name: "item_speed_boost",
            size: size,
            directory: directory
        ) { context in
            drawWings(in: context, color: UIColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1))
        }

        // Damage Boost - Orange sword
        try generateSprite(
            name: "item_damage_boost",
            size: size,
            directory: directory
        ) { context in
            drawSword(in: context, color: UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1))
        }

        // Shield Orb - Blue shield
        try generateSprite(
            name: "item_shield_orb",
            size: size,
            directory: directory
        ) { context in
            drawShield(in: context, color: UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1))
        }

        // Ammo Cache - Yellow ammunition box
        try generateSprite(
            name: "item_ammo_cache",
            size: size,
            directory: directory
        ) { context in
            drawAmmoBox(in: context, color: UIColor(red: 0.9, green: 0.9, blue: 0.2, alpha: 1))
        }

        // XP Multiplier - Purple star
        try generateSprite(
            name: "item_xp_multiplier",
            size: size,
            directory: directory
        ) { context in
            drawStar(in: context, color: UIColor(red: 0.8, green: 0.4, blue: 1.0, alpha: 1), points: 5)
        }

        // Armor Shard - Gray armor piece
        try generateSprite(
            name: "item_armor_shard",
            size: size,
            directory: directory
        ) { context in
            drawArmorShard(in: context, color: UIColor(red: 0.6, green: 0.6, blue: 0.7, alpha: 1))
        }

        // Dungeon Key - Gold key
        try generateSprite(
            name: "item_dungeon_key",
            size: size,
            directory: directory
        ) { context in
            drawKey(in: context, color: UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1))
        }

        // Rare Treasure - Magenta gem
        try generateSprite(
            name: "item_rare_treasure",
            size: size,
            directory: directory
        ) { context in
            drawGem(in: context, color: UIColor(red: 1.0, green: 0.3, blue: 0.9, alpha: 1))
        }

        print("  Generated \(ItemType.allCases.count) item sprites")
    }

    // MARK: - UI Icon Sprites

    private static func generateUIIcons(to directory: URL) throws {
        let iconSize = CGSize(width: 24, height: 24)

        // Heart icon for health
        try generateSprite(
            name: "icon_heart",
            size: iconSize,
            directory: directory
        ) { context in
            drawHeart(in: context, color: UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1))
        }

        // Star icon for XP
        try generateSprite(
            name: "icon_xp_star",
            size: iconSize,
            directory: directory
        ) { context in
            drawStar(in: context, color: UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1), points: 5)
        }

        // Skull icon for kills
        try generateSprite(
            name: "icon_skull",
            size: CGSize(width: 20, height: 20),
            directory: directory
        ) { context in
            drawSkull(in: context, color: UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1))
        }

        // Pause icon
        try generateSprite(
            name: "icon_pause",
            size: CGSize(width: 32, height: 32),
            directory: directory
        ) { context in
            drawPause(in: context, color: UIColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 1))
        }

        // Attack icon (crossed swords)
        try generateSprite(
            name: "icon_attack",
            size: iconSize,
            directory: directory
        ) { context in
            drawCrossedSwords(in: context, color: UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1))
        }

        // Defense icon (shield)
        try generateSprite(
            name: "icon_defense",
            size: iconSize,
            directory: directory
        ) { context in
            drawShield(in: context, color: UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1))
        }

        // Speed icon (boot/wing)
        try generateSprite(
            name: "icon_speed",
            size: iconSize,
            directory: directory
        ) { context in
            drawWings(in: context, color: UIColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1))
        }

        print("  Generated 7 UI icon sprites")
    }

    // MARK: - Entity Sprites

    private static func generateEntitySprites(to directory: URL) throws {
        // Player sprite
        try generateSprite(
            name: "player_idle",
            size: CGSize(width: 32, height: 40),
            directory: directory
        ) { context in
            drawPlayer(in: context)
        }

        // Enemy sprite
        try generateSprite(
            name: "enemy_basic",
            size: CGSize(width: 28, height: 36),
            directory: directory
        ) { context in
            drawEnemy(in: context)
        }

        // Bullet sprite
        try generateSprite(
            name: "bullet_basic",
            size: CGSize(width: 8, height: 8),
            directory: directory
        ) { context in
            drawBullet(in: context)
        }

        // Shadow sprites
        try generateSprite(
            name: "player_shadow",
            size: CGSize(width: 24, height: 12),
            directory: directory
        ) { context in
            drawShadow(in: context, width: 24)
        }

        try generateSprite(
            name: "enemy_shadow",
            size: CGSize(width: 20, height: 10),
            directory: directory
        ) { context in
            drawShadow(in: context, width: 20)
        }

        print("  Generated 5 entity sprites")
    }

    // MARK: - Sprite Generation Helper

    private static func generateSprite(
        name: String,
        size: CGSize,
        directory: URL,
        draw: (CGContext) -> Void
    ) throws {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { rendererContext in
            let context = rendererContext.cgContext

            // Clear background (transparent)
            context.clear(CGRect(origin: .zero, size: size))

            // Call custom drawing
            draw(context)
        }

        // Save as PNG
        if let pngData = image.pngData() {
            let fileURL = directory.appendingPathComponent("\(name).png")
            try pngData.write(to: fileURL)
        }
    }

    // MARK: - Drawing Functions

    private static func drawPotion(in context: CGContext, color: UIColor, scale: CGFloat = 1.0) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let baseRadius: CGFloat = 10 * scale

        // Bottle body (rounded rectangle)
        context.setFillColor(color.cgColor)
        let bottleRect = CGRect(
            x: center.x - baseRadius * 0.6,
            y: center.y - baseRadius * 0.4,
            width: baseRadius * 1.2,
            height: baseRadius * 1.5
        )
        let path = UIBezierPath(roundedRect: bottleRect, cornerRadius: baseRadius * 0.3)
        context.addPath(path.cgPath)
        context.fillPath()

        // Neck
        context.setFillColor(color.withAlphaComponent(0.8).cgColor)
        let neckRect = CGRect(
            x: center.x - baseRadius * 0.3,
            y: center.y - baseRadius * 1.1,
            width: baseRadius * 0.6,
            height: baseRadius * 0.7
        )
        context.fill(neckRect)

        // Cork/stopper
        context.setFillColor(UIColor(red: 0.55, green: 0.45, blue: 0.35, alpha: 1).cgColor)
        let corkRect = CGRect(
            x: center.x - baseRadius * 0.25,
            y: center.y - baseRadius * 1.3,
            width: baseRadius * 0.5,
            height: baseRadius * 0.3
        )
        context.fill(corkRect)
    }

    private static func drawSword(in context: CGContext, color: UIColor) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        context.setFillColor(color.cgColor)

        // Blade (diagonal)
        let blade = UIBezierPath()
        blade.move(to: CGPoint(x: center.x - 8, y: center.y + 8))
        blade.addLine(to: CGPoint(x: center.x + 8, y: center.y - 8))
        blade.addLine(to: CGPoint(x: center.x + 6, y: center.y - 10))
        blade.addLine(to: CGPoint(x: center.x - 10, y: center.y + 6))
        blade.close()
        context.addPath(blade.cgPath)
        context.fillPath()

        // Hilt (crossguard)
        context.setFillColor(UIColor(red: 0.6, green: 0.5, blue: 0.3, alpha: 1).cgColor)
        let hilt = CGRect(x: center.x - 10, y: center.y + 6, width: 6, height: 2)
        context.fill(hilt)
    }

    private static func drawShield(in context: CGContext, color: UIColor) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius: CGFloat = 10

        // Shield shape (rounded bottom)
        let shield = UIBezierPath()
        shield.move(to: CGPoint(x: center.x, y: center.y - radius))
        shield.addArc(
            withCenter: CGPoint(x: center.x + radius * 0.7, y: center.y),
            radius: radius,
            startAngle: .pi * 1.3,
            endAngle: .pi * 0.2,
            clockwise: false
        )
        shield.addLine(to: CGPoint(x: center.x, y: center.y + radius * 1.2))
        shield.addArc(
            withCenter: CGPoint(x: center.x - radius * 0.7, y: center.y),
            radius: radius,
            startAngle: .pi * 0.8,
            endAngle: .pi * 1.7,
            clockwise: false
        )
        shield.close()

        context.setFillColor(color.cgColor)
        context.addPath(shield.cgPath)
        context.fillPath()

        // Cross emblem
        context.setFillColor(UIColor.white.withAlphaComponent(0.7).cgColor)
        context.fill(CGRect(x: center.x - 1, y: center.y - 6, width: 2, height: 12))
        context.fill(CGRect(x: center.x - 5, y: center.y - 1, width: 10, height: 2))
    }

    private static func drawWings(in context: CGContext, color: UIColor) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        context.setFillColor(color.cgColor)

        // Left wing
        let leftWing = UIBezierPath()
        leftWing.move(to: center)
        leftWing.addQuadCurve(
            to: CGPoint(x: center.x - 10, y: center.y),
            controlPoint: CGPoint(x: center.x - 8, y: center.y - 6)
        )
        leftWing.addQuadCurve(
            to: center,
            controlPoint: CGPoint(x: center.x - 8, y: center.y + 6)
        )
        leftWing.close()
        context.addPath(leftWing.cgPath)
        context.fillPath()

        // Right wing
        let rightWing = UIBezierPath()
        rightWing.move(to: center)
        rightWing.addQuadCurve(
            to: CGPoint(x: center.x + 10, y: center.y),
            controlPoint: CGPoint(x: center.x + 8, y: center.y - 6)
        )
        rightWing.addQuadCurve(
            to: center,
            controlPoint: CGPoint(x: center.x + 8, y: center.y + 6)
        )
        rightWing.close()
        context.addPath(rightWing.cgPath)
        context.fillPath()
    }

    private static func drawStar(in context: CGContext, color: UIColor, points: Int) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius: CGFloat = 10
        let innerRadius: CGFloat = radius * 0.4

        let path = UIBezierPath()
        for i in 0..<(points * 2) {
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let r = i % 2 == 0 ? radius : innerRadius
            let x = center.x + r * cos(angle)
            let y = center.y + r * sin(angle)

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.close()

        context.setFillColor(color.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
    }

    private static func drawGem(in context: CGContext, color: UIColor) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        // Diamond/gem shape
        let gem = UIBezierPath()
        gem.move(to: CGPoint(x: center.x, y: center.y - 10))  // Top
        gem.addLine(to: CGPoint(x: center.x + 7, y: center.y - 3))  // Top right
        gem.addLine(to: CGPoint(x: center.x + 5, y: center.y + 10))  // Bottom right
        gem.addLine(to: CGPoint(x: center.x, y: center.y + 8))  // Bottom center
        gem.addLine(to: CGPoint(x: center.x - 5, y: center.y + 10))  // Bottom left
        gem.addLine(to: CGPoint(x: center.x - 7, y: center.y - 3))  // Top left
        gem.close()

        context.setFillColor(color.cgColor)
        context.addPath(gem.cgPath)
        context.fillPath()

        // Facets (lighter color)
        context.setFillColor(color.withAlphaComponent(0.5).cgColor)
        context.fill(CGRect(x: center.x - 1, y: center.y - 8, width: 2, height: 15))
    }

    private static func drawKey(in context: CGContext, color: UIColor) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        context.setFillColor(color.cgColor)

        // Key head (circle with hole)
        context.addEllipse(in: CGRect(x: center.x - 5, y: center.y - 10, width: 10, height: 10))
        context.fillPath()

        context.setFillColor(UIColor.black.withAlphaComponent(0.3).cgColor)
        context.addEllipse(in: CGRect(x: center.x - 2, y: center.y - 7, width: 4, height: 4))
        context.fillPath()

        // Key shaft
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: center.x - 1, y: center.y, width: 2, height: 12))

        // Key teeth
        context.fill(CGRect(x: center.x + 1, y: center.y + 8, width: 3, height: 2))
        context.fill(CGRect(x: center.x + 1, y: center.y + 11, width: 3, height: 2))
    }

    private static func drawAmmoBox(in context: CGContext, color: UIColor) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        // Box
        context.setFillColor(color.cgColor)
        let box = CGRect(x: center.x - 8, y: center.y - 6, width: 16, height: 12)
        context.fill(box)

        // Bullets/shells (circles)
        context.setFillColor(UIColor(red: 0.7, green: 0.6, blue: 0.4, alpha: 1).cgColor)
        for i in 0..<3 {
            let x = center.x - 4 + CGFloat(i) * 4
            context.addEllipse(in: CGRect(x: x - 1.5, y: center.y - 3, width: 3, height: 6))
        }
        context.fillPath()
    }

    private static func drawArmorShard(in context: CGContext, color: UIColor) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        // Armor plate (rounded rectangle)
        context.setFillColor(color.cgColor)
        let armor = UIBezierPath(
            roundedRect: CGRect(x: center.x - 8, y: center.y - 9, width: 16, height: 18),
            cornerRadius: 3
        )
        context.addPath(armor.cgPath)
        context.fillPath()

        // Rivets
        context.setFillColor(UIColor(red: 0.4, green: 0.4, blue: 0.5, alpha: 1).cgColor)
        for x in [-5, 5] {
            for y in [-6, 0, 6] {
                context.addEllipse(in: CGRect(
                    x: center.x + CGFloat(x) - 1,
                    y: center.y + CGFloat(y) - 1,
                    width: 2,
                    height: 2
                ))
            }
        }
        context.fillPath()
    }

    private static func drawHeart(in context: CGContext, color: UIColor) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        let heart = UIBezierPath()
        heart.move(to: CGPoint(x: center.x, y: center.y + 8))

        // Left side
        heart.addQuadCurve(
            to: CGPoint(x: center.x - 8, y: center.y - 2),
            controlPoint: CGPoint(x: center.x - 8, y: center.y + 4)
        )
        heart.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y - 6),
            controlPoint: CGPoint(x: center.x - 8, y: center.y - 8)
        )

        // Right side
        heart.addQuadCurve(
            to: CGPoint(x: center.x + 8, y: center.y - 2),
            controlPoint: CGPoint(x: center.x + 8, y: center.y - 8)
        )
        heart.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y + 8),
            controlPoint: CGPoint(x: center.x + 8, y: center.y + 4)
        )
        heart.close()

        context.setFillColor(color.cgColor)
        context.addPath(heart.cgPath)
        context.fillPath()
    }

    private static func drawSkull(in context: CGContext, color: UIColor) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        // Head (rounded)
        context.setFillColor(color.cgColor)
        context.addEllipse(in: CGRect(x: center.x - 6, y: center.y - 7, width: 12, height: 10))
        context.fillPath()

        // Jaw
        let jaw = CGRect(x: center.x - 4, y: center.y + 2, width: 8, height: 4)
        context.fill(jaw)

        // Eye sockets (dark)
        context.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor)
        context.addEllipse(in: CGRect(x: center.x - 5, y: center.y - 4, width: 3, height: 4))
        context.addEllipse(in: CGRect(x: center.x + 2, y: center.y - 4, width: 3, height: 4))
        context.fillPath()
    }

    private static func drawPause(in context: CGContext, color: UIColor) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        context.setFillColor(color.cgColor)

        // Two vertical bars
        context.fill(CGRect(x: center.x - 7, y: center.y - 10, width: 4, height: 20))
        context.fill(CGRect(x: center.x + 3, y: center.y - 10, width: 4, height: 20))
    }

    private static func drawCrossedSwords(in context: CGContext, color: UIColor) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        context.setFillColor(color.cgColor)

        // First sword (top-left to bottom-right)
        let sword1 = UIBezierPath()
        sword1.move(to: CGPoint(x: center.x - 6, y: center.y - 6))
        sword1.addLine(to: CGPoint(x: center.x + 6, y: center.y + 6))
        sword1.lineWidth = 2
        sword1.stroke()

        // Second sword (top-right to bottom-left)
        let sword2 = UIBezierPath()
        sword2.move(to: CGPoint(x: center.x + 6, y: center.y - 6))
        sword2.addLine(to: CGPoint(x: center.x - 6, y: center.y + 6))
        sword2.lineWidth = 2
        sword2.stroke()
    }

    private static func drawPlayer(in context: CGContext) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        // Body (blue)
        context.setFillColor(UIColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1).cgColor)
        let body = CGRect(x: center.x - 10, y: center.y - 12, width: 20, height: 24)
        context.fill(body)

        // Head
        context.setFillColor(UIColor(red: 0.9, green: 0.8, blue: 0.7, alpha: 1).cgColor)
        context.addEllipse(in: CGRect(x: center.x - 6, y: center.y - 18, width: 12, height: 12))
        context.fillPath()

        // Weapon indicator (white)
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: center.x + 8, y: center.y - 8, width: 3, height: 12))
    }

    private static func drawEnemy(in context: CGContext) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        // Body (red)
        context.setFillColor(UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1).cgColor)
        let body = CGRect(x: center.x - 9, y: center.y - 10, width: 18, height: 20)
        context.fill(body)

        // Eyes (white)
        context.setFillColor(UIColor.white.cgColor)
        context.addEllipse(in: CGRect(x: center.x - 5, y: center.y - 6, width: 3, height: 4))
        context.addEllipse(in: CGRect(x: center.x + 2, y: center.y - 6, width: 3, height: 4))
        context.fillPath()
    }

    private static func drawBullet(in context: CGContext) {
        let bounds = context.boundingBoxOfClipPath

        // Simple yellow circle
        context.setFillColor(UIColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1).cgColor)
        context.addEllipse(in: bounds)
        context.fillPath()

        // Bright center
        context.setFillColor(UIColor.white.withAlphaComponent(0.7).cgColor)
        context.addEllipse(in: bounds.insetBy(dx: 2, dy: 2))
        context.fillPath()
    }

    private static func drawShadow(in context: CGContext, width: CGFloat) {
        let bounds = context.boundingBoxOfClipPath
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        // Semi-transparent black ellipse
        context.setFillColor(UIColor.black.withAlphaComponent(0.3).cgColor)
        context.addEllipse(in: CGRect(
            x: center.x - width / 2,
            y: center.y - width / 5,
            width: width,
            height: width / 2.5
        ))
        context.fillPath()
    }
}
