import SpriteKit

/// Main menu title screen with Play, Codex, and Settings buttons
class MainMenuScreen: SKScene {
    // MARK: - UI Elements

    private var titleLabel: MedievalLabel!
    private var playButton: MedievalButton!
    private var codexButton: MedievalButton!
    private var settingsButton: MedievalButton!
    private var versionLabel: MedievalLabel!

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        setupBackground()
        setupTitle()
        setupButtons()
        setupFooter()
        animateEntrance()
    }

    // MARK: - Setup

    private func setupBackground() {
        // Dark stone background with vignette effect
        backgroundColor = UITheme.darkStone

        // Add subtle parchment texture overlay
        let overlaySize = size
        let parchmentOverlay = SKShapeNode(rectOf: overlaySize)
        parchmentOverlay.fillColor = UITheme.parchmentDark.withAlphaComponent(0.1)
        parchmentOverlay.strokeColor = .clear
        parchmentOverlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        parchmentOverlay.zPosition = 0
        addChild(parchmentOverlay)
    }

    private func setupTitle() {
        // Game title with ornamental frame
        let titlePanel = MedievalPanel(size: CGSize(width: 600, height: 120))
        titlePanel.position = CGPoint(x: size.width / 2, y: size.height / 2 + 150)
        titlePanel.zPosition = 10
        addChild(titlePanel)

        // Title text
        titleLabel = MedievalLabel(text: "REALM OF SHADOWS", style: .title, withShadow: true)
        titleLabel.position = CGPoint(x: 0, y: 0)
        titlePanel.addContent(titleLabel)

        // Subtitle
        let subtitle = MedievalLabel(text: "An Isometric Adventure", style: .small, withShadow: false, color: UITheme.textGray)
        subtitle.position = CGPoint(x: 0, y: -30)
        titlePanel.addContent(subtitle)
    }

    private func setupButtons() {
        let buttonSpacing: CGFloat = UITheme.spacingLarge + 10
        let startY = size.height / 2 - 50

        // Play Button
        playButton = MedievalButton.large(text: "PLAY")
        playButton.position = CGPoint(x: size.width / 2, y: startY)
        playButton.zPosition = 10
        playButton.onTap = { [weak self] in
            self?.startGame()
        }
        addChild(playButton)

        // Codex Button
        codexButton = MedievalButton(text: "CODEX")
        codexButton.position = CGPoint(x: size.width / 2, y: startY - buttonSpacing)
        codexButton.zPosition = 10
        codexButton.onTap = { [weak self] in
            self?.openCodex()
        }
        addChild(codexButton)

        // Settings Button
        settingsButton = MedievalButton(text: "SETTINGS")
        settingsButton.position = CGPoint(x: size.width / 2, y: startY - buttonSpacing * 2)
        settingsButton.zPosition = 10
        settingsButton.onTap = { [weak self] in
            self?.openSettings()
        }
        addChild(settingsButton)
    }

    private func setupFooter() {
        // Version label
        versionLabel = MedievalLabel(text: "v1.0", style: .small, withShadow: false, color: UITheme.textGray)
        versionLabel.position = CGPoint(x: size.width / 2, y: 40)
        versionLabel.zPosition = 10
        addChild(versionLabel)

        // Copyright
        let copyright = MedievalLabel(text: "© 2026", style: .small, withShadow: false, color: UITheme.textGray)
        copyright.position = CGPoint(x: size.width / 2 + 100, y: 40)
        copyright.zPosition = 10
        addChild(copyright)
    }

    // MARK: - Animations

    private func animateEntrance() {
        // Fade in title
        titleLabel.alpha = 0
        titleLabel.run(UIAnimations.fadeIn(duration: UITheme.animationSlow))

        // Slide in buttons with stagger
        playButton.position.y -= 100
        playButton.alpha = 0
        playButton.run(SKAction.sequence([
            UIAnimations.wait(0.2),
            SKAction.group([
                UIAnimations.slideIn(from: .down, distance: 100),
                UIAnimations.fadeIn()
            ])
        ]))

        codexButton.position.y -= 100
        codexButton.alpha = 0
        codexButton.run(SKAction.sequence([
            UIAnimations.wait(0.3),
            SKAction.group([
                UIAnimations.slideIn(from: .down, distance: 100),
                UIAnimations.fadeIn()
            ])
        ]))

        settingsButton.position.y -= 100
        settingsButton.alpha = 0
        settingsButton.run(SKAction.sequence([
            UIAnimations.wait(0.4),
            SKAction.group([
                UIAnimations.slideIn(from: .down, distance: 100),
                UIAnimations.fadeIn()
            ])
        ]))
    }

    // MARK: - Actions

    private func startGame() {
        // Transition to game scene
        let gameScene = GameScene(size: size)
        gameScene.scaleMode = .resizeFill
        view?.presentScene(gameScene, transition: SKTransition.fade(withDuration: UITheme.animationSlow))
    }

    private func openCodex() {
        // TODO: Implement in Phase 4
        print("[MainMenu] Codex not yet implemented")
    }

    private func openSettings() {
        // TODO: Implement in Phase 4
        print("[MainMenu] Settings not yet implemented")
    }
}
