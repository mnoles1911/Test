import SpriteKit

/// Enhanced heads-up display with medieval theming
/// Features: health/XP bars with ornamental frames, level display, kill counter, minimap, pause button
final class EnhancedHUD: SKNode {
    // MARK: - Components

    private var healthBar: StatBar!
    private var xpBar: StatBar!
    private var levelLabel: MedievalLabel!
    private var killsLabel: MedievalLabel!
    private var pauseButton: MedievalButton!
    private var minimap: Minimap!

    // MARK: - Properties

    var onPauseTapped: (() -> Void)?

    // MARK: - Initialization

    override init() {
        super.init()
        zPosition = Constants.ZPosition.hud

        setupBars()
        setupLabels()
        setupPauseButton()
        setupMinimap()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupBars() {
        // Phase 5: Heart icon for health bar
        let heartIcon = SKSpriteNode(texture: SpriteManager.shared.getIconSprite("heart"))
        heartIcon.size = CGSize(width: 20, height: 20)
        heartIcon.name = "heartIcon"
        heartIcon.zPosition = 1
        addChild(heartIcon)

        // Health bar
        healthBar = StatBar(
            size: CGSize(width: 180, height: 18),
            maxValue: 100,
            fillColor: UITheme.forestGreen
        )
        healthBar.zPosition = 1
        addChild(healthBar)

        // Phase 5: Star icon for XP bar
        let xpIcon = SKSpriteNode(texture: SpriteManager.shared.getIconSprite("xp_star"))
        xpIcon.size = CGSize(width: 18, height: 18)
        xpIcon.name = "xpIcon"
        xpIcon.zPosition = 1
        addChild(xpIcon)

        // XP bar below health (blue)
        xpBar = StatBar(
            size: CGSize(width: 180, height: 12),
            maxValue: 100,
            fillColor: UITheme.royalBlue
        )
        xpBar.setFixedColor(UITheme.royalBlue) // Don't change color based on ratio
        xpBar.hideLabel() // XP bar doesn't need label
        xpBar.zPosition = 1
        addChild(xpBar)
    }

    private func setupLabels() {
        // Level label
        levelLabel = MedievalLabel(text: "LVL 1", style: .header, withShadow: true)
        levelLabel.setHorizontalAlignment(.left)
        levelLabel.zPosition = 1
        addChild(levelLabel)

        // Kills counter
        killsLabel = MedievalLabel(text: "Kills: 0", style: .body, withShadow: true)
        killsLabel.setHorizontalAlignment(.right)
        killsLabel.zPosition = 1
        addChild(killsLabel)
    }

    private func setupPauseButton() {
        pauseButton = MedievalButton.small(text: "⏸")
        pauseButton.zPosition = 1
        pauseButton.onTap = { [weak self] in
            self?.onPauseTapped?()
        }
        addChild(pauseButton)
    }

    private func setupMinimap() {
        minimap = Minimap(size: CGSize(width: 120, height: 120))
        minimap.zPosition = 1
        addChild(minimap)
    }

    // MARK: - Layout

    func layout(screenSize: CGSize) {
        let left = -screenSize.width / 2 + 20
        let top = screenSize.height / 2 - 30
        let right = screenSize.width / 2 - 20

        // Heart icon (to the left of health bar)
        if let heartIcon = childNode(withName: "heartIcon") {
            heartIcon.position = CGPoint(x: left, y: top)
        }

        // Health bar (top-left)
        healthBar.position = CGPoint(x: left + 100, y: top)

        // XP star icon (to the left of XP bar)
        if let xpIcon = childNode(withName: "xpIcon") {
            xpIcon.position = CGPoint(x: left, y: top - 24)
        }

        // XP bar (below health bar)
        xpBar.position = CGPoint(x: left + 100, y: top - 24)

        // Level label (below XP bar)
        levelLabel.position = CGPoint(x: left, y: top - 48)

        // Kills label (top-right)
        killsLabel.position = CGPoint(x: right, y: top)

        // Pause button (top-right, below kills)
        pauseButton.position = CGPoint(x: right - 45, y: top - 40)

        // Minimap (top-right corner, below pause button)
        minimap.position = CGPoint(x: right - 60, y: top - 130)
    }

    // MARK: - Update

    func update(player: Player, enemies: [Enemy], killCount: Int, currentTime: TimeInterval) {
        // Update health bar
        healthBar.update(value: CGFloat(player.health), animated: true)
        healthBar.setMaxValue(CGFloat(player.maxHealth))

        // Update XP bar
        xpBar.update(value: CGFloat(player.experience), animated: true)
        xpBar.setMaxValue(CGFloat(player.experienceToNext))

        // Update labels
        levelLabel.text = "LVL \(player.level)"
        killsLabel.text = "Kills: \(killCount)"

        // Update minimap
        minimap.update(playerPosition: player.worldPosition, enemies: enemies, currentTime: currentTime)
    }

    // MARK: - Minimap Management

    func setWorldManager(_ worldManager: WorldManager) {
        minimap.setWorldManager(worldManager)
    }

    func showMinimap() {
        minimap.show()
    }

    func hideMinimap() {
        minimap.hide()
    }
}
