import SpriteKit

final class Bullet {
    let node: SKNode
    var worldPosition: CGPoint
    let direction: CGPoint
    let speed: CGFloat
    let damage: Int
    let spawnTime: TimeInterval
    var isExpired: Bool = false

    init(worldPosition: CGPoint, direction: CGPoint, speed: CGFloat = Constants.bulletSpeed,
         damage: Int = Constants.bulletDamage, spawnTime: TimeInterval) {
        self.worldPosition = worldPosition
        self.direction = direction
        self.speed = speed
        self.damage = damage
        self.spawnTime = spawnTime

        // Phase 5: Use bullet sprite
        let container = SKNode()
        let texture = SpriteManager.shared.getEntitySprite("bullet_basic")
        let sprite = SKSpriteNode(texture: texture)
        sprite.size = CGSize(width: 6, height: 6)
        container.addChild(sprite)

        // Add a glow effect
        let glow = SKShapeNode(circleOfRadius: 6)
        glow.fillColor = SKColor.yellow.withAlphaComponent(0.3)
        glow.strokeColor = .clear
        glow.zPosition = -0.1
        container.addChild(glow)

        container.zPosition = Constants.ZPosition.bullet
        container.name = "bullet"
        node = container

        syncPosition()
    }

    func update(deltaTime: TimeInterval, currentTime: TimeInterval) {
        let move = speed * CGFloat(deltaTime) / Constants.tileWidth
        worldPosition = CGPoint(
            x: worldPosition.x + direction.x * move,
            y: worldPosition.y + direction.y * move
        )
        syncPosition()

        if currentTime - spawnTime > Constants.bulletLifetime {
            isExpired = true
        }
    }

    private func syncPosition() {
        node.position = IsometricMath.worldToScreen(worldPosition)
    }

    func remove() {
        // Small impact effect
        if let parent = node.parent {
            let spark = SKShapeNode(circleOfRadius: 5)
            spark.fillColor = .orange
            spark.strokeColor = .clear
            spark.position = node.position
            spark.zPosition = Constants.ZPosition.bullet
            parent.addChild(spark)

            spark.run(SKAction.sequence([
                SKAction.group([
                    SKAction.scale(to: 2.0, duration: 0.1),
                    SKAction.fadeOut(withDuration: 0.15)
                ]),
                SKAction.removeFromParent()
            ]))
        }
        node.removeFromParent()
    }
}
