import SpriteKit

final class Enemy: Entity {
    enum State {
        case idle
        case chasing
        case attacking
    }

    var state: State = .idle
    var lastAttackTime: TimeInterval = 0
    let experienceValue: Int = 25

    init(worldPosition: CGPoint) {
        let node = Enemy.createEnemyNode()
        super.init(worldPosition: worldPosition, health: Constants.enemyMaxHealth, node: node)
        node.zPosition = Constants.ZPosition.entity
        node.name = "enemy"
    }

    private static func createEnemyNode() -> SKNode {
        let container = SKNode()

        // Body
        let body = SKShapeNode(rectOf: Constants.enemySize, cornerRadius: 2)
        body.fillColor = SKColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)
        body.strokeColor = SKColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1)
        body.lineWidth = 1.5
        container.addChild(body)

        // Eyes
        let eyeSize: CGFloat = 3
        let leftEye = SKShapeNode(circleOfRadius: eyeSize)
        leftEye.fillColor = .white
        leftEye.strokeColor = .clear
        leftEye.position = CGPoint(x: -4, y: 4)
        container.addChild(leftEye)

        let rightEye = SKShapeNode(circleOfRadius: eyeSize)
        rightEye.fillColor = .white
        rightEye.strokeColor = .clear
        rightEye.position = CGPoint(x: 4, y: 4)
        container.addChild(rightEye)

        // Shadow
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 16, height: 7))
        shadow.fillColor = SKColor.black.withAlphaComponent(0.3)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -Constants.enemySize.height / 2)
        shadow.zPosition = Constants.ZPosition.shadow - Constants.ZPosition.entity
        container.addChild(shadow)

        // Health bar background
        let hpBg = SKShapeNode(rectOf: CGSize(width: 22, height: 3))
        hpBg.fillColor = SKColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 0.8)
        hpBg.strokeColor = .clear
        hpBg.position = CGPoint(x: 0, y: Constants.enemySize.height / 2 + 6)
        hpBg.name = "hpBg"
        container.addChild(hpBg)

        let hpBar = SKShapeNode(rectOf: CGSize(width: 20, height: 2))
        hpBar.fillColor = .green
        hpBar.strokeColor = .clear
        hpBar.position = CGPoint(x: 0, y: Constants.enemySize.height / 2 + 6)
        hpBar.name = "hpBar"
        container.addChild(hpBar)

        return container
    }

    func updateAI(playerPosition: CGPoint, currentTime: TimeInterval) {
        let dist = IsometricMath.distance(worldPosition, playerPosition)

        switch state {
        case .idle:
            if dist < Constants.enemyDetectionRange / Constants.tileWidth {
                state = .chasing
            }
        case .chasing:
            if dist < Constants.enemyAttackRange / Constants.tileWidth {
                state = .attacking
            } else if dist > Constants.enemyDetectionRange / Constants.tileWidth * 1.5 {
                state = .idle
            } else {
                moveToward(playerPosition)
            }
        case .attacking:
            if dist > Constants.enemyAttackRange / Constants.tileWidth * 1.2 {
                state = .chasing
            }
        }
    }

    private func moveToward(_ target: CGPoint) {
        let dir = IsometricMath.direction(from: worldPosition, to: target)
        let speed = Constants.enemySpeed / Constants.tileWidth * (1.0 / 60.0) // approx per-frame
        worldPosition = CGPoint(
            x: worldPosition.x + dir.x * speed,
            y: worldPosition.y + dir.y * speed
        )
    }

    func canAttack(currentTime: TimeInterval) -> Bool {
        return state == .attacking && (currentTime - lastAttackTime) >= Constants.enemyAttackCooldown
    }

    override func update(deltaTime: TimeInterval) {
        // Update health bar
        if let hpBar = node.childNode(withName: "hpBar") as? SKShapeNode {
            let ratio = CGFloat(health) / CGFloat(maxHealth)
            hpBar.xScale = max(ratio, 0)
            hpBar.fillColor = ratio > 0.5 ? .green : (ratio > 0.25 ? .yellow : .red)
        }

        node.zPosition = Constants.ZPosition.entity + (worldPosition.x + worldPosition.y) * 0.01

        super.update(deltaTime: deltaTime)
    }

    override func onDeath() {
        // Drop XP orb visual
        let orb = SKShapeNode(circleOfRadius: 5)
        orb.fillColor = .yellow
        orb.strokeColor = .orange
        orb.position = node.position
        orb.zPosition = Constants.ZPosition.entity
        orb.name = "xpOrb_\(experienceValue)"
        node.parent?.addChild(orb)

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.3, duration: 0.3),
            SKAction.scale(to: 0.8, duration: 0.3)
        ])
        let fadeAndRemove = SKAction.sequence([
            SKAction.wait(forDuration: 5.0),
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ])
        orb.run(SKAction.group([SKAction.repeatForever(pulse), fadeAndRemove]))

        super.onDeath()
    }
}
