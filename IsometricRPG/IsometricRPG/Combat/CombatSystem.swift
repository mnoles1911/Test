import SpriteKit

/// Manages all active bullets and handles hit detection.
final class CombatSystem {
    private(set) var bullets: [Bullet] = []
    private weak var worldNode: SKNode?

    init(worldNode: SKNode) {
        self.worldNode = worldNode
    }

    func fireBullet(from origin: CGPoint, direction: CGPoint, at time: TimeInterval) {
        let bullet = Bullet(worldPosition: origin, direction: direction, spawnTime: time)
        bullets.append(bullet)
        worldNode?.addChild(bullet.node)

        // Muzzle flash
        if let worldNode = worldNode {
            let flash = SKShapeNode(circleOfRadius: 8)
            flash.fillColor = SKColor.white.withAlphaComponent(0.8)
            flash.strokeColor = .clear
            flash.position = IsometricMath.worldToScreen(origin)
            flash.zPosition = Constants.ZPosition.bullet + 1
            worldNode.addChild(flash)
            flash.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.08),
                SKAction.removeFromParent()
            ]))
        }
    }

    func update(deltaTime: TimeInterval, currentTime: TimeInterval, enemies: inout [Enemy], player: Player) {
        // Update bullets
        for bullet in bullets {
            bullet.update(deltaTime: deltaTime, currentTime: currentTime)
        }

        // Bullet-enemy collisions
        for bullet in bullets where !bullet.isExpired {
            for enemy in enemies where enemy.isAlive {
                let dist = IsometricMath.distance(bullet.worldPosition, enemy.worldPosition)
                if dist < 0.5 { // half a tile
                    enemy.takeDamage(bullet.damage)
                    bullet.isExpired = true

                    if !enemy.isAlive {
                        player.gainExperience(enemy.experienceValue)
                    }
                    break
                }
            }
        }

        // Clean up expired bullets
        let expired = bullets.filter { $0.isExpired }
        for bullet in expired {
            bullet.remove()
        }
        bullets.removeAll { $0.isExpired }

        // Clean up dead enemies
        enemies.removeAll { !$0.isAlive && $0.node.parent == nil }
    }

    func removeAll() {
        for bullet in bullets {
            bullet.node.removeFromParent()
        }
        bullets.removeAll()
    }
}
