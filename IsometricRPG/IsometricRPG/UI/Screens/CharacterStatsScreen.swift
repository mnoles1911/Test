import SpriteKit

/// Character stats screen showing player attributes, level, and equipment bonuses
class CharacterStatsScreen: ModalOverlay {
    // MARK: - UI Elements

    private var panel: MedievalPanel!
    private var portraitNode: SKShapeNode!
    private var nameLabel: MedievalLabel!
    private var levelLabel: MedievalLabel!

    private var healthLabel: MedievalLabel!
    private var attackLabel: MedievalLabel!
    private var defenseLabel: MedievalLabel!
    private var speedLabel: MedievalLabel!
    private var armorLabel: MedievalLabel!
    private var keysLabel: MedievalLabel!

    private var xpBar: StatBar!
    private var closeButton: MedievalButton!

    // MARK: - Data

    private var player: Player

    // MARK: - Callbacks

    var onClose: (() -> Void)?

    // MARK: - Initialization

    init(screenSize: CGSize, player: Player) {
        self.player = player

        super.init(screenSize: screenSize)

        setupPanel()
        setupPortrait()
        setupLabels()
        setupStats()
        setupXPBar()
        setupCloseButton()

        refreshStats()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupPanel() {
        panel = MedievalPanel.large(title: "CHARACTER")
        panel.position = CGPoint(x: 0, y: 0)
        panel.zPosition = Constants.ZPosition.modalContent
        addChild(panel)
    }

    private func setupPortrait() {
        // Character portrait (placeholder - blue square representing player)
        let portraitSize: CGFloat = 80
        portraitNode = SKShapeNode(rectOf: CGSize(width: portraitSize, height: portraitSize), cornerRadius: 8)
        portraitNode.fillColor = SKColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        portraitNode.strokeColor = UITheme.gold
        portraitNode.lineWidth = 3
        portraitNode.position = CGPoint(x: -250, y: 150)
        panel.addContent(portraitNode)
    }

    private func setupLabels() {
        // Character name
        nameLabel = MedievalLabel(text: "Adventurer", style: .header, withShadow: true, color: UITheme.textGold)
        nameLabel.position = CGPoint(x: -100, y: 180)
        nameLabel.setHorizontalAlignment(.left)
        panel.addContent(nameLabel)

        // Level and class
        levelLabel = MedievalLabel(text: "Level 1 Warrior", style: .body, withShadow: true)
        levelLabel.position = CGPoint(x: -100, y: 155)
        levelLabel.setHorizontalAlignment(.left)
        panel.addContent(levelLabel)
    }

    private func setupStats() {
        let leftX: CGFloat = -250
        let rightX: CGFloat = 100
        let startY: CGFloat = 80
        let spacing: CGFloat = 40

        // Left column
        healthLabel = createStatLabel(icon: "❤️", text: "Health:", at: CGPoint(x: leftX, y: startY))
        attackLabel = createStatLabel(icon: "⚔️", text: "Attack:", at: CGPoint(x: leftX, y: startY - spacing))
        defenseLabel = createStatLabel(icon: "🛡️", text: "Defense:", at: CGPoint(x: leftX, y: startY - spacing * 2))

        // Right column
        speedLabel = createStatLabel(icon: "👟", text: "Speed:", at: CGPoint(x: rightX, y: startY))
        armorLabel = createStatLabel(icon: "🔰", text: "Armor:", at: CGPoint(x: rightX, y: startY - spacing))
        keysLabel = createStatLabel(icon: "🔑", text: "Keys:", at: CGPoint(x: rightX, y: startY - spacing * 2))
    }

    private func createStatLabel(icon: String, text: String, at position: CGPoint) -> MedievalLabel {
        let label = MedievalLabel(text: "\(icon) \(text) 0", style: .body, withShadow: true)
        label.position = position
        label.setHorizontalAlignment(.left)
        panel.addContent(label)
        return label
    }

    private func setupXPBar() {
        xpBar = StatBar(size: CGSize(width: 400, height: 20), maxValue: 100, fillColor: UITheme.royalBlue)
        xpBar.setFixedColor(UITheme.royalBlue)
        xpBar.position = CGPoint(x: 0, y: -100)
        panel.addContent(xpBar)

        let xpLabel = MedievalLabel(text: "Experience", style: .body, withShadow: true)
        xpLabel.position = CGPoint(x: 0, y: -75)
        panel.addContent(xpLabel)
    }

    private func setupCloseButton() {
        closeButton = MedievalButton.small(text: "CLOSE")
        closeButton.position = CGPoint(x: 0, y: -230)
        closeButton.onTap = { [weak self] in
            self?.onClose?()
            self?.dismiss(animated: true)
        }
        panel.addContent(closeButton)
    }

    // MARK: - Update

    private func refreshStats() {
        // Update level
        levelLabel.text = "Level \(player.level) Warrior"

        // Calculate equipment bonuses
        let attackBonus = player.equipment.totalAttackBonus
        let defenseBonus = player.equipment.totalDefenseBonus

        // Update stats
        healthLabel.text = "❤️ Health: \(player.health) / \(player.maxHealth)"
        attackLabel.text = "⚔️ Attack: \(player.totalAttack)" + (attackBonus > 0 ? " (+\(attackBonus))" : "")
        defenseLabel.text = "🛡️ Defense: \(player.totalDefense)" + (defenseBonus > 0 ? " (+\(defenseBonus))" : "")
        speedLabel.text = "👟 Speed: \(Int(Constants.playerSpeed))"
        armorLabel.text = "🔰 Armor: \(player.armor)"
        keysLabel.text = "🔑 Keys: \(player.keys)"

        // Update XP bar
        xpBar.update(value: CGFloat(player.experience), animated: false)
        xpBar.setMaxValue(CGFloat(player.experienceToNext))
    }
}
