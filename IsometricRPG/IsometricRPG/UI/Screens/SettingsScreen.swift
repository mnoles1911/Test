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
        // Phase 5: Sound and music labels removed - now using toggle buttons in setupToggles()

        joystickLabel = MedievalLabel(text: "🕹️ Joystick: Normal", style: .body, withShadow: true)
        joystickLabel.position = CGPoint(x: -150, y: -50)
        joystickLabel.setHorizontalAlignment(.left)
        panel.addContent(joystickLabel)
    }

    private func setupToggles() {
        let startY: CGFloat = 80

        // Phase 5: Sound toggle
        let soundToggle = MedievalButton(
            text: AudioManager.shared.isSoundEnabled ? "🔊 Sound: ON" : "🔊 Sound: OFF",
            size: CGSize(width: 200, height: 40)
        )
        soundToggle.position = CGPoint(x: 0, y: startY)
        soundToggle.onTap = { [weak self] in
            self?.toggleSound(button: soundToggle)
        }
        panel.addContent(soundToggle)

        // Phase 5: Music toggle
        let musicToggle = MedievalButton(
            text: AudioManager.shared.isMusicEnabled ? "🎵 Music: ON" : "🎵 Music: OFF",
            size: CGSize(width: 200, height: 40)
        )
        musicToggle.position = CGPoint(x: 0, y: startY - 50)
        musicToggle.onTap = { [weak self] in
            self?.toggleMusic(button: musicToggle)
        }
        panel.addContent(musicToggle)

        // FPS toggle
        fpsToggle = MedievalButton(
            text: settings.showFPS ? "📊 FPS: ON" : "📊 FPS: OFF",
            size: CGSize(width: 200, height: 40)
        )
        fpsToggle.position = CGPoint(x: 0, y: startY - 100)
        fpsToggle.onTap = { [weak self] in
            self?.toggleFPS()
        }
        panel.addContent(fpsToggle)

        // Minimap toggle
        minimapToggle = MedievalButton(
            text: settings.showMinimap ? "🗺️ Minimap: ON" : "🗺️ Minimap: OFF",
            size: CGSize(width: 200, height: 40)
        )
        minimapToggle.position = CGPoint(x: 0, y: startY - 150)
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

    // Phase 5: Toggle sound effects
    private func toggleSound(button: MedievalButton) {
        AudioManager.shared.isSoundEnabled.toggle()
        button.text = AudioManager.shared.isSoundEnabled ? "🔊 Sound: ON" : "🔊 Sound: OFF"
    }

    // Phase 5: Toggle background music
    private func toggleMusic(button: MedievalButton) {
        AudioManager.shared.isMusicEnabled.toggle()
        button.text = AudioManager.shared.isMusicEnabled ? "🎵 Music: ON" : "🎵 Music: OFF"
    }

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
