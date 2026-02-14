import SpriteKit

enum BuffType: CustomStringConvertible {
    case speed
    case damage
    case shield
    case fireRate
    case xpBoost

    var description: String {
        switch self {
        case .speed:    return "speed"
        case .damage:   return "damage"
        case .shield:   return "shield"
        case .fireRate: return "fireRate"
        case .xpBoost:  return "xpBoost"
        }
    }
}

struct ActiveBuff {
    let type: BuffType
    let multiplier: CGFloat
    var remainingDuration: TimeInterval
}

final class Player: Entity {
    var moveDirection: CGPoint = .zero
    var aimDirection: CGPoint = .zero
    var isShooting: Bool = false
    private var lastFireTime: TimeInterval = 0

    // RPG stats
    var level: Int = 1
    var experience: Int = 0
    var experienceToNext: Int = 100
    var armor: Int = 0
    var keys: Int = 0

    // Buffs
    private(set) var activeBuffs: [ActiveBuff] = []

    init(worldPosition: CGPoint) {
        let node = Player.createPlayerNode()
        super.init(worldPosition: worldPosition, health: Constants.playerMaxHealth, node: node)
        node.zPosition = Constants.ZPosition.entity
        node.name = "player"
    }

    private static func createPlayerNode() -> SKNode {
        let container = SKNode()

        let body = SKShapeNode(rectOf: Constants.playerSize, cornerRadius: 3)
        body.fillColor = SKColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        body.strokeColor = SKColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 1)
        body.lineWidth = 1.5
        container.addChild(body)

        let indicator = SKShapeNode(circleOfRadius: 3)
        indicator.fillColor = .white
        indicator.strokeColor = .clear
        indicator.position = CGPoint(x: 0, y: Constants.playerSize.height / 2 + 4)
        indicator.name = "aimIndicator"
        container.addChild(indicator)

        let shadow = SKShapeNode(ellipseOf: CGSize(width: 18, height: 8))
        shadow.fillColor = SKColor.black.withAlphaComponent(0.3)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -Constants.playerSize.height / 2)
        shadow.zPosition = Constants.ZPosition.shadow - Constants.ZPosition.entity
        container.addChild(shadow)

        return container
    }

    override func update(deltaTime: TimeInterval) {
        if moveDirection != .zero {
            let speedMultiplier = buffMultiplier(for: .speed)
            let speed = Constants.playerSpeed * CGFloat(deltaTime) * speedMultiplier
            worldPosition = CGPoint(
                x: worldPosition.x + moveDirection.x * speed / Constants.tileWidth,
                y: worldPosition.y + moveDirection.y * speed / Constants.tileHeight
            )
        }

        if aimDirection != .zero {
            let angle = atan2(aimDirection.y, aimDirection.x) - .pi / 2
            if let indicator = node.childNode(withName: "aimIndicator") {
                let radius: CGFloat = Constants.playerSize.height / 2 + 4
                indicator.position = CGPoint(
                    x: cos(angle + .pi / 2) * radius,
                    y: sin(angle + .pi / 2) * radius
                )
            }
        }

        node.zPosition = Constants.ZPosition.entity + (worldPosition.x + worldPosition.y) * 0.01
        super.update(deltaTime: deltaTime)
    }

    // MARK: - Combat

    func canFire(currentTime: TimeInterval) -> Bool {
        let rateMultiplier = buffMultiplier(for: .fireRate)
        let effectiveRate = Constants.fireRate * TimeInterval(rateMultiplier)
        return isShooting && aimDirection != .zero && (currentTime - lastFireTime) >= effectiveRate
    }

    func didFire(at time: TimeInterval) {
        lastFireTime = time
    }

    func effectiveDamage() -> Int {
        let mult = buffMultiplier(for: .damage)
        return Int(CGFloat(Constants.bulletDamage) * mult)
    }

    override func takeDamage(_ amount: Int) {
        var reduced = amount
        let shieldMult = buffMultiplier(for: .shield)
        if shieldMult < 1.0 {
            reduced = Int(CGFloat(amount) * shieldMult)
        }
        if armor > 0 {
            let absorbed = min(armor, reduced / 2)
            armor -= absorbed
            reduced -= absorbed
        }
        super.takeDamage(max(reduced, 1))
    }

    // MARK: - Healing & Items

    func heal(amount: Int) {
        health = min(health + amount, maxHealth)

        let label = SKLabelNode(text: "+\(amount)")
        label.fontName = "Helvetica-Bold"
        label.fontSize = 12
        label.fontColor = .green
        label.position = CGPoint(x: 0, y: 25)
        label.zPosition = 50
        node.addChild(label)
        let rise = SKAction.moveBy(x: 0, y: 15, duration: 0.6)
        let fade = SKAction.fadeOut(withDuration: 0.4)
        label.run(SKAction.sequence([SKAction.group([rise, fade]), SKAction.removeFromParent()]))
    }

    func addArmor(_ amount: Int) {
        armor += amount
    }

    func addKey() {
        keys += 1
    }

    // MARK: - Buff System

    func applyBuff(_ type: BuffType, duration: TimeInterval, multiplier: CGFloat) {
        activeBuffs.removeAll { $0.type == type }
        node.childNode(withName: "buff_\(type)")?.removeFromParent()

        activeBuffs.append(ActiveBuff(type: type, multiplier: multiplier, remainingDuration: duration))

        let indicator = SKShapeNode(circleOfRadius: 12)
        indicator.fillColor = buffColor(type).withAlphaComponent(0.2)
        indicator.strokeColor = buffColor(type)
        indicator.lineWidth = 1
        indicator.name = "buff_\(type)"
        indicator.zPosition = -0.2
        node.addChild(indicator)

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.3, duration: 0.4),
            SKAction.scale(to: 0.9, duration: 0.4)
        ])
        indicator.run(SKAction.repeatForever(pulse))
    }

    func updateBuffs(deltaTime: TimeInterval) {
        var expired: [BuffType] = []
        for i in 0..<activeBuffs.count {
            activeBuffs[i].remainingDuration -= deltaTime
            if activeBuffs[i].remainingDuration <= 0 {
                expired.append(activeBuffs[i].type)
            }
        }
        for type in expired {
            node.childNode(withName: "buff_\(type)")?.removeFromParent()
        }
        activeBuffs.removeAll { $0.remainingDuration <= 0 }
    }

    func buffMultiplier(for type: BuffType) -> CGFloat {
        if let buff = activeBuffs.first(where: { $0.type == type }) {
            return buff.multiplier
        }
        return 1.0
    }

    var activeBuffCount: Int { activeBuffs.count }

    private func buffColor(_ type: BuffType) -> SKColor {
        switch type {
        case .speed:    return .cyan
        case .damage:   return .orange
        case .shield:   return .blue
        case .fireRate: return .yellow
        case .xpBoost:  return .purple
        }
    }

    // MARK: - Experience

    func gainExperience(_ amount: Int) {
        let mult = buffMultiplier(for: .xpBoost)
        let total = Int(CGFloat(amount) * mult)
        experience += total
        while experience >= experienceToNext {
            levelUp()
        }
    }

    private func levelUp() {
        level += 1
        experience -= experienceToNext
        experienceToNext = Int(Double(experienceToNext) * 1.5)
        maxHealth += 10
        health = maxHealth

        let label = SKLabelNode(text: "LEVEL UP!")
        label.fontName = "Helvetica-Bold"
        label.fontSize = 14
        label.fontColor = .yellow
        label.position = CGPoint(x: 0, y: 30)
        label.zPosition = 50
        node.addChild(label)

        let rise = SKAction.moveBy(x: 0, y: 20, duration: 1.0)
        let fade = SKAction.fadeOut(withDuration: 1.0)
        label.run(SKAction.sequence([SKAction.group([rise, fade]), SKAction.removeFromParent()]))
    }
}
