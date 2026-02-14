import SpriteKit

/// An item placed in the world that the player can pick up.
final class WorldItem {
    let itemType: ItemType
    var worldPosition: CGPoint
    let node: SKNode
    var isPickedUp = false

    init(itemType: ItemType, worldPosition: CGPoint) {
        self.itemType = itemType
        self.worldPosition = worldPosition
        self.node = WorldItem.createNode(for: itemType)
        syncPosition()

        // Idle hover animation
        let hover = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 3, duration: 0.8),
            SKAction.moveBy(x: 0, y: -3, duration: 0.8)
        ])
        node.run(SKAction.repeatForever(hover))
    }

    private static func createNode(for type: ItemType) -> SKNode {
        let container = SKNode()
        container.name = "item_\(type)"

        // Glow
        let glow = SKShapeNode(circleOfRadius: type.size + 4)
        glow.fillColor = type.glowColor
        glow.strokeColor = .clear
        glow.zPosition = -0.1

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.3, duration: 0.6),
            SKAction.scale(to: 0.9, duration: 0.6)
        ])
        glow.run(SKAction.repeatForever(pulse))
        container.addChild(glow)

        // Item shape varies by category
        let shape: SKShapeNode
        switch type.category {
        case .consumable:
            // Circle (potion bottle)
            shape = SKShapeNode(circleOfRadius: type.size)
        case .weapon:
            // Diamond
            let path = CGMutablePath()
            let s = type.size
            path.move(to: CGPoint(x: 0, y: s))
            path.addLine(to: CGPoint(x: s, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -s))
            path.addLine(to: CGPoint(x: -s, y: 0))
            path.closeSubpath()
            shape = SKShapeNode(path: path)
        case .armor:
            // Square (shield)
            shape = SKShapeNode(rectOf: CGSize(width: type.size * 2, height: type.size * 2), cornerRadius: 2)
        case .treasure:
            // Star shape (simplified as larger circle)
            shape = SKShapeNode(circleOfRadius: type.size)
        case .special:
            // Triangle (key/rare)
            let path = CGMutablePath()
            let s = type.size
            path.move(to: CGPoint(x: 0, y: s + 2))
            path.addLine(to: CGPoint(x: s, y: -s / 2))
            path.addLine(to: CGPoint(x: -s, y: -s / 2))
            path.closeSubpath()
            shape = SKShapeNode(path: path)
        }

        shape.fillColor = type.color
        shape.strokeColor = type.color.withAlphaComponent(0.8)
        shape.lineWidth = 1
        container.addChild(shape)

        container.zPosition = Constants.ZPosition.item

        return container
    }

    func syncPosition() {
        node.position = IsometricMath.worldToScreen(worldPosition)
        node.zPosition = Constants.ZPosition.item + (worldPosition.x + worldPosition.y) * 0.001
    }

    func pickup() {
        isPickedUp = true
        let collect = SKAction.group([
            SKAction.scale(to: 1.5, duration: 0.15),
            SKAction.fadeOut(withDuration: 0.2)
        ])
        node.run(SKAction.sequence([collect, SKAction.removeFromParent()]))
    }

    /// Apply this item's effect to the player.
    func applyEffect(to player: Player) {
        switch itemType {
        case .healthPotion:
            player.heal(amount: 25)
        case .healthPotionLarge:
            player.heal(amount: 50)
        case .speedBoost:
            player.applyBuff(.speed, duration: 10.0, multiplier: 1.5)
        case .damageBoost:
            player.applyBuff(.damage, duration: 8.0, multiplier: 2.0)
        case .shieldOrb:
            player.applyBuff(.shield, duration: 12.0, multiplier: 0.5)
        case .ammoCache:
            player.applyBuff(.fireRate, duration: 8.0, multiplier: 0.5)
        case .xpMultiplier:
            player.applyBuff(.xpBoost, duration: 15.0, multiplier: 2.0)
        case .armorShard:
            player.addArmor(5)
        case .dungeonKey:
            player.addKey()
        case .rareTreasure:
            player.gainExperience(200)
        }
    }
}
