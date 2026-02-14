import SpriteKit

/// Codex screen displaying lore entries in a book-style interface
class CodexScreen: ModalOverlay {
    // MARK: - UI Elements

    private var panel: MedievalPanel!
    private var categoryButtons: [MedievalButton] = []
    private var entryButtons: [MedievalButton] = []
    private var detailsPanel: MedievalPanel!
    private var titleLabel: MedievalLabel!
    private var descriptionLabel: MedievalLabel!
    private var progressLabel: MedievalLabel!
    private var closeButton: MedievalButton!

    // MARK: - Data

    private var allEntries: [LoreEntry]
    private var selectedCategory: LoreEntry.Category = .enemies
    private var selectedEntry: LoreEntry?

    // MARK: - Callbacks

    var onClose: (() -> Void)?

    // MARK: - Initialization

    init(screenSize: CGSize, entries: [LoreEntry]) {
        self.allEntries = entries

        super.init(screenSize: screenSize)

        setupPanel()
        setupCategories()
        setupEntryList()
        setupDetailsPanel()
        setupProgressLabel()
        setupCloseButton()

        selectCategory(.enemies)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupPanel() {
        panel = MedievalPanel(size: CGSize(width: 800, height: 550), title: "CODEX OF LORE")
        panel.position = CGPoint(x: 0, y: 0)
        panel.zPosition = Constants.ZPosition.modalContent
        addChild(panel)
    }

    private func setupCategories() {
        let categories: [LoreEntry.Category] = [.enemies, .items, .lore, .world]
        let buttonWidth: CGFloat = 120
        let spacing: CGFloat = 10
        let startX: CGFloat = -350
        let y: CGFloat = 200

        for (index, category) in categories.enumerated() {
            let button = MedievalButton(
                text: "\(category.icon) \(category.displayName)",
                size: CGSize(width: buttonWidth, height: 40)
            )
            button.position = CGPoint(x: startX + CGFloat(index) * (buttonWidth + spacing), y: y)
            button.onTap = { [weak self] in
                self?.selectCategory(category)
            }
            panel.addContent(button)
            categoryButtons.append(button)
        }
    }

    private func setupEntryList() {
        // Entry list will be dynamically created based on selected category
    }

    private func setupDetailsPanel() {
        detailsPanel = MedievalPanel(size: CGSize(width: 450, height: 380))
        detailsPanel.position = CGPoint(x: 125, y: 20)
        panel.addContent(detailsPanel)

        titleLabel = MedievalLabel(text: "Select an entry", style: .header, withShadow: true, color: UITheme.textGold)
        titleLabel.position = CGPoint(x: 0, y: 150)
        detailsPanel.addContent(titleLabel)

        descriptionLabel = MedievalLabel(text: "", style: .body, withShadow: false, color: UITheme.textDark)
        descriptionLabel.position = CGPoint(x: 0, y: 80)
        detailsPanel.addContent(descriptionLabel)
    }

    private func setupProgressLabel() {
        progressLabel = MedievalLabel(text: "Discovered: 0/0", style: .small, withShadow: false, color: UITheme.textGray)
        progressLabel.position = CGPoint(x: -250, y: -220)
        panel.addContent(progressLabel)
        updateProgress()
    }

    private func setupCloseButton() {
        closeButton = MedievalButton.small(text: "CLOSE")
        closeButton.position = CGPoint(x: 300, y: -230)
        closeButton.onTap = { [weak self] in
            self?.onClose?()
            self?.dismiss(animated: true)
        }
        panel.addContent(closeButton)
    }

    // MARK: - Category Selection

    private func selectCategory(_ category: LoreEntry.Category) {
        selectedCategory = category

        // Clear existing entry buttons
        for button in entryButtons {
            button.removeFromParent()
        }
        entryButtons.removeAll()

        // Get entries for this category
        let entries = allEntries.filter { $0.category == category }

        // Create entry buttons
        let startY: CGFloat = 130
        let spacing: CGFloat = 50
        let buttonWidth: CGFloat = 220

        for (index, entry) in entries.enumerated() {
            let displayText = entry.isUnlocked ? entry.title : "???"
            let button = MedievalButton(
                text: displayText,
                size: CGSize(width: buttonWidth, height: 40)
            )
            button.position = CGPoint(x: -230, y: startY - CGFloat(index) * spacing)

            if entry.isUnlocked {
                button.onTap = { [weak self] in
                    self?.selectEntry(entry)
                }
            } else {
                button.isEnabled = false
            }

            panel.addContent(button)
            entryButtons.append(button)
        }

        updateProgress()
    }

    // MARK: - Entry Selection

    private func selectEntry(_ entry: LoreEntry) {
        selectedEntry = entry

        titleLabel.text = entry.title
        titleLabel.fontColor = UITheme.textGold

        // Word wrap description (basic implementation - split at ~40 chars)
        let words = entry.description.split(separator: " ")
        var lines: [String] = []
        var currentLine = ""

        for word in words {
            let testLine = currentLine.isEmpty ? String(word) : currentLine + " " + String(word)
            if testLine.count > 40 && !currentLine.isEmpty {
                lines.append(currentLine)
                currentLine = String(word)
            } else {
                currentLine = testLine
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        // Display first 6 lines (limited space)
        let displayText = lines.prefix(6).joined(separator: "\n")
        descriptionLabel.text = displayText
    }

    // MARK: - Progress

    private func updateProgress() {
        let categoryEntries = allEntries.filter { $0.category == selectedCategory }
        let unlockedCount = categoryEntries.filter { $0.isUnlocked }.count
        let totalCount = categoryEntries.count

        progressLabel.text = "Discovered: \(unlockedCount)/\(totalCount)"
    }

    // MARK: - Public Methods

    /// Update entries (call when new entries are unlocked)
    func updateEntries(_ entries: [LoreEntry]) {
        self.allEntries = entries
        selectCategory(selectedCategory) // Refresh current view
    }
}
