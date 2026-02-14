import SpriteKit

/// Floating damage/XP numbers that appear on hit
/// Color-coded: red (damage to player), yellow (XP gain), white (critical hits)
class DamageNumber {
    // MARK: - Type

    enum NumberType {
        case damage        // Red, damage to player
        case xp            // Yellow, XP gained
        case critical      // White, critical hit
        case healing       // Green, healing

        var color: SKColor {
            switch self {
            case .damage:   return UITheme.crimson
            case .xp:       return SKColor.yellow
            case .critical: return SKColor.white
            case .healing:  return UITheme.forestGreen
            }
        }
    }

    // MARK: - Spawn

    /// Spawn a floating damage number at the given world position
    static func spawn(value: Int, type: NumberType, at position: CGPoint, in scene: SKNode) {
        // Create label
        let label = SKLabelNode(fontNamed: UITheme.titleFont)
        label.text = type == .damage || type == .critical ? "-\(value)" : "+\(value)"
        label.fontSize = type == .critical ? 20 : 16
        label.fontColor = type.color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = position
        label.zPosition = Constants.ZPosition.hud - 10 // Below HUD but above game

        // Add outline for readability
        let outline = SKLabelNode(fontNamed: UITheme.titleFont)
        outline.text = label.text
        outline.fontSize = label.fontSize
        outline.fontColor = UITheme.shadowColor
        outline.verticalAlignmentMode = .center
        outline.horizontalAlignmentMode = .center
        outline.position = CGPoint(x: 1, y: -1)
        outline.zPosition = -1
        label.addChild(outline)

        scene.addChild(label)

        // Animation: rise + fade + slight arc
        let arcOffset: CGFloat = type == .critical ? 20 : 10
        let riseDistance: CGFloat = type == .critical ? 60 : 40
        let duration: TimeInterval = type == .critical ? 1.2 : 1.0

        let moveUp = SKAction.moveBy(x: arcOffset, y: riseDistance, duration: duration)
        moveUp.timingMode = .easeOut

        let fadeOut = SKAction.fadeOut(withDuration: duration * 0.7)
        fadeOut.timingMode = .easeIn

        let scale = type == .critical ?
            SKAction.sequence([
                SKAction.scale(to: 1.3, duration: duration * 0.3),
                SKAction.scale(to: 1.0, duration: duration * 0.7)
            ]) :
            SKAction.scale(to: 1.0, duration: 0.01) // No scale for normal

        let group = SKAction.group([moveUp, fadeOut, scale])
        let remove = SKAction.removeFromParent()

        label.run(SKAction.sequence([group, remove]))
    }

    /// Convenience method for damage to player
    static func showDamage(_ value: Int, at position: CGPoint, in scene: SKNode) {
        spawn(value: value, type: .damage, at: position, in: scene)
    }

    /// Convenience method for XP gain
    static func showXP(_ value: Int, at position: CGPoint, in scene: SKNode) {
        spawn(value: value, type: .xp, at: position, in: scene)
    }

    /// Convenience method for critical hit
    static func showCritical(_ value: Int, at position: CGPoint, in scene: SKNode) {
        spawn(value: value, type: .critical, at: position, in: scene)
    }

    /// Convenience method for healing
    static func showHealing(_ value: Int, at position: CGPoint, in scene: SKNode) {
        spawn(value: value, type: .healing, at: position, in: scene)
    }
}
