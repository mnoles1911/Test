import SpriteKit

/// Pause menu overlay with options: Resume, Inventory, Character, Settings, Main Menu
class PauseMenuScreen: ModalOverlay {
    // MARK: - UI Elements

    private var panel: MedievalPanel!
    private var resumeButton: MedievalButton!
    private var inventoryButton: MedievalButton!
    private var characterButton: MedievalButton!
    private var settingsButton: MedievalButton!
    private var mainMenuButton: MedievalButton!

    // MARK: - Callbacks

    var onResume: (() -> Void)?
    var onInventory: (() -> Void)?
    var onCharacter: (() -> Void)?
    var onSettings: (() -> Void)?
    var onMainMenu: (() -> Void)?

    // MARK: - Initialization

    init(screenSize: CGSize) {
        super.init(screenSize: screenSize)

        setupPanel()
        setupButtons()
        setupTitle()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupPanel() {
        panel = MedievalPanel.medium(title: "GAME PAUSED")
        panel.position = CGPoint(x: 0, y: 0)
        panel.zPosition = Constants.ZPosition.modalContent
        addChild(panel)
    }

    private func setupButtons() {
        let buttonSpacing: CGFloat = UITheme.spacingLarge + 10
        let startY: CGFloat = 80

        // Resume Button
        resumeButton = MedievalButton(text: "RESUME")
        resumeButton.position = CGPoint(x: 0, y: startY)
        resumeButton.onTap = { [weak self] in
            self?.onResume?()
            self?.dismiss(animated: true)
        }
        panel.addContent(resumeButton)

        // Inventory Button
        inventoryButton = MedievalButton(text: "INVENTORY")
        inventoryButton.position = CGPoint(x: 0, y: startY - buttonSpacing)
        inventoryButton.onTap = { [weak self] in
            self?.onInventory?()
        }
        panel.addContent(inventoryButton)

        // Character Button
        characterButton = MedievalButton(text: "CHARACTER")
        characterButton.position = CGPoint(x: 0, y: startY - buttonSpacing * 2)
        characterButton.onTap = { [weak self] in
            self?.onCharacter?()
        }
        panel.addContent(characterButton)

        // Settings Button
        settingsButton = MedievalButton(text: "SETTINGS")
        settingsButton.position = CGPoint(x: 0, y: startY - buttonSpacing * 3)
        settingsButton.onTap = { [weak self] in
            self?.onSettings?()
        }
        panel.addContent(settingsButton)

        // Main Menu Button
        mainMenuButton = MedievalButton(text: "MAIN MENU")
        mainMenuButton.position = CGPoint(x: 0, y: startY - buttonSpacing * 4)
        mainMenuButton.onTap = { [weak self] in
            self?.onMainMenu?()
        }
        panel.addContent(mainMenuButton)
    }

    private func setupTitle() {
        // Title is set via panel's title parameter
        // Additional subtitle can be added here if needed
    }
}
