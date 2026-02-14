import SpriteKit

/// Heads-up display: health bar, level, score, XP bar.
/// This node is added to the camera so it stays fixed on screen.
final class HUD: SKNode {
    private let healthBarBg: SKShapeNode
    private let healthBarFill: SKShapeNode
    private let xpBarBg: SKShapeNode
    private let xpBarFill: SKShapeNode
    private let levelLabel: SKLabelNode
    private let killsLabel: SKLabelNode

    private let barWidth: CGFloat = 150
    private let barHeight: CGFloat = 12
    private let xpBarHeight: CGFloat = 6

    var kills: Int = 0

    override init() {
        // Health bar
        healthBarBg = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 3)
        healthBarBg.fillColor = SKColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.8)
        healthBarBg.strokeColor = SKColor.white.withAlphaComponent(0.5)
        healthBarBg.lineWidth = 1

        healthBarFill = SKShapeNode(rectOf: CGSize(width: barWidth - 4, height: barHeight - 4), cornerRadius: 2)
        healthBarFill.fillColor = SKColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1)
        healthBarFill.strokeColor = .clear

        // XP bar
        xpBarBg = SKShapeNode(rectOf: CGSize(width: barWidth, height: xpBarHeight), cornerRadius: 2)
        xpBarBg.fillColor = SKColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.8)
        xpBarBg.strokeColor = SKColor.white.withAlphaComponent(0.3)
        xpBarBg.lineWidth = 0.5

        xpBarFill = SKShapeNode(rectOf: CGSize(width: barWidth - 4, height: xpBarHeight - 2), cornerRadius: 1)
        xpBarFill.fillColor = SKColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1)
        xpBarFill.strokeColor = .clear

        // Labels
        levelLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        levelLabel.fontSize = 14
        levelLabel.fontColor = .white
        levelLabel.horizontalAlignmentMode = .left

        killsLabel = SKLabelNode(fontNamed: "Helvetica")
        killsLabel.fontSize = 12
        killsLabel.fontColor = .white
        killsLabel.horizontalAlignmentMode = .right

        super.init()
        zPosition = Constants.ZPosition.hud

        addChild(healthBarBg)
        addChild(healthBarFill)
        addChild(xpBarBg)
        addChild(xpBarFill)
        addChild(levelLabel)
        addChild(killsLabel)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layout(screenSize: CGSize) {
        let left = -screenSize.width / 2 + 20
        let top = screenSize.height / 2 - 40
        let right = screenSize.width / 2 - 20

        healthBarBg.position = CGPoint(x: left + barWidth / 2, y: top)
        healthBarFill.position = CGPoint(x: left + barWidth / 2, y: top)

        xpBarBg.position = CGPoint(x: left + barWidth / 2, y: top - barHeight - 4)
        xpBarFill.position = CGPoint(x: left + barWidth / 2, y: top - barHeight - 4)

        levelLabel.position = CGPoint(x: left, y: top - barHeight - 24)
        killsLabel.position = CGPoint(x: right, y: top)
    }

    func update(player: Player, killCount: Int) {
        // Health
        let healthRatio = CGFloat(player.health) / CGFloat(player.maxHealth)
        healthBarFill.xScale = max(healthRatio, 0)
        if healthRatio > 0.5 {
            healthBarFill.fillColor = SKColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1)
        } else if healthRatio > 0.25 {
            healthBarFill.fillColor = .yellow
        } else {
            healthBarFill.fillColor = .red
        }

        // XP
        let xpRatio = CGFloat(player.experience) / CGFloat(max(player.experienceToNext, 1))
        xpBarFill.xScale = max(min(xpRatio, 1), 0)

        // Labels
        levelLabel.text = "LVL \(player.level)"
        kills = killCount
        killsLabel.text = "Kills: \(killCount)"
    }
}
