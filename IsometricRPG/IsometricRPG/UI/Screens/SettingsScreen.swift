import SpriteKit

/// Settings screen for game options and preferences
class SettingsScreen: ModalOverlay {
    // MARK: - UI Elements

    private var panel: MedievalPanel!
    private var minimapToggle: MedievalButton!
    private var fpsToggle: MedievalButton!
    private var saveButton: MedievalButton!
    private var closeButton: MedievalButton!

    // Labels
    private var soundLabel: MedievalLabel!
    private var musicLabel: MedievalLabel!
    private var joystickLabel: MedievalLabel!

    // MARK: - Settings

    private var settings: SaveManager.GameSettings

    // MARK: - Callbacks

    var onClose: (() -> Void)?
    var onSettingsChanged: ((SaveManager.GameSettings) -> Void)?

    // MARK: - Initialization

    init(screenSize: CGSize) {
        // Load current settings
        self.settings = SaveManager.shared.loadSettings()

        super.init(screenSize: screenSize)

        setupPanel()
        setupToggles()
        setupButtons()
        setupLabels()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupPanel() {
        panel = MedievalPanel.medium(title: "SETTINGS")
        panel.position = CGPoint(x: 0, y: 0)
        panel.zPosition = Constants.ZPosition.modalContent
        addChild(panel)
    }

    private func setupLabels() {
        let startY: CGFloat = 100

        soundLabel = MedievalLabel(text: "🔊 Sound: ON", style: .body, withShadow: true)
        soundLabel.position = CGPoint(x: -150, y: startY)
        soundLabel.setHorizontalAlignment(.left)
        panel.addContent(soundLabel)

        musicLabel = MedievalLabel(text: "🎵 Music: ON", style: .body, withShadow: true)
        musicLabel.position = CGPoint(x: -150, y: startY - 50)
        musicLabel.setHorizontalAlignment(.left)
        panel.addContent(musicLabel)

        joystickLabel = MedievalLabel(text: "🕹️ Joystick: Normal", style: .body, withShadow: true)
        joystickLabel.position = CGPoint(x: -150, y: startY - 100)
        joystickLabel.setHorizontalAlignment(.left)
        panel.addContent(joystickLabel)
    }

    private func setupToggles() {
        let startY: CGFloat = -20

        // FPS toggle
        fpsToggle = MedievalButton(
            text: settings.showFPS ? "📊 FPS: ON" : "📊 FPS: OFF",
            size: CGSize(width: 200, height: 40)
        )
        fpsToggle.position = CGPoint(x: 0, y: startY)
        fpsToggle.onTap = { [weak self] in
            self?.toggleFPS()
        }
        panel.addContent(fpsToggle)

        // Minimap toggle
        minimapToggle = MedievalButton(
            text: settings.showMinimap ? "🗺️ Minimap: ON" : "🗺️ Minimap: OFF",
            size: CGSize(width: 200, height: 40)
        )
        minimapToggle.position = CGPoint(x: 0, y: startY - 50)
        minimapToggle.onTap = { [weak self] in
            self?.toggleMinimap()
        }
        panel.addContent(minimapToggle)
    }

    private func setupButtons() {
        // Save button
        saveButton = MedievalButton(text: "SAVE", size: CGSize(width: 150, height: 40))
        saveButton.position = CGPoint(x: -80, y: -140)
        saveButton.onTap = { [weak self] in
            self?.saveSettings()
        }
        panel.addContent(saveButton)

        // Close button
        closeButton = MedievalButton.small(text: "CLOSE")
        closeButton.position = CGPoint(x: 80, y: -140)
        closeButton.onTap = { [weak self] in
            self?.onClose?()
            self?.dismiss(animated: true)
        }
        panel.addContent(closeButton)
    }

    // MARK: - Actions

    private func toggleFPS() {
        settings.showFPS.toggle()
        fpsToggle.text = settings.showFPS ? "📊 FPS: ON" : "📊 FPS: OFF"
    }

    private func toggleMinimap() {
        settings.showMinimap.toggle()
        minimapToggle.text = settings.showMinimap ? "🗺️ Minimap: ON" : "🗺️ Minimap: OFF"
    }

    private func saveSettings() {
        SaveManager.shared.saveSettings(settings)
        onSettingsChanged?(settings)

        // Visual feedback
        let label = SKLabelNode(text: "Settings Saved!")
        label.fontName = UITheme.titleFont
        label.fontSize = 16
        label.fontColor = UITheme.textGold
        label.position = CGPoint(x: 0, y: -100)
        label.zPosition = 100
        panel.addContent(label)

        let fadeOut = SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ])
        label.run(fadeOut)
    }
}
