import SpriteKit

/// Base class for all game entities (player, enemies, NPCs).
/// Entities live in *world space* (grid coordinates) and their screen-space
/// position is computed via IsometricMath.
class Entity {
    var worldPosition: CGPoint
    var health: Int
    var maxHealth: Int
    var isAlive: Bool { health > 0 }
    let node: SKNode

    init(worldPosition: CGPoint, health: Int, node: SKNode) {
        self.worldPosition = worldPosition
        self.health = health
        self.maxHealth = health
        self.node = node
        syncNodePosition()
    }

    func syncNodePosition() {
        node.position = IsometricMath.worldToScreen(worldPosition)
    }

    func takeDamage(_ amount: Int) {
        health = max(0, health - amount)
        if !isAlive {
            onDeath()
        } else {
            onHit()
        }
    }

    func onHit() {
        // Flash red
        let flash = SKAction.sequence([
            SKAction.colorize(with: .red, colorBlendFactor: 1.0, duration: 0.05),
            SKAction.colorize(withColorBlendFactor: 0.0, duration: 0.1)
        ])
        if let sprite = node as? SKSpriteNode {
            sprite.run(flash)
        } else if let shape = node.children.first as? SKShapeNode {
            let original = shape.fillColor
            let flashAction = SKAction.sequence([
                SKAction.run { shape.fillColor = .red },
                SKAction.wait(forDuration: 0.1),
                SKAction.run { shape.fillColor = original }
            ])
            shape.run(flashAction)
        }
    }

    func onDeath() {
        let fadeOut = SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.3),
            SKAction.removeFromParent()
        ])
        node.run(fadeOut)
    }

    func update(deltaTime: TimeInterval) {
        syncNodePosition()
    }
}
