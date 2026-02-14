import SpriteKit

/// Inventory screen with equipment slots and backpack grid
/// Displays item details on selection
class InventoryScreen: ModalOverlay {
    // MARK: - UI Elements

    private var panel: MedievalPanel!
    private var equipmentGrid: InventoryGrid!
    private var backpackGrid: InventoryGrid!
    private var itemDetailsPanel: MedievalPanel!
    private var itemNameLabel: MedievalLabel!
    private var itemDescLabel: MedievalLabel!
    private var itemStatsLabel: MedievalLabel!
    private var capacityLabel: MedievalLabel!
    private var closeButton: MedievalButton!

    // MARK: - Data

    private var inventory: [Item?] = []
    private var equipment: Equipment = Equipment()

    // MARK: - Callbacks

    var onClose: (() -> Void)?

    // MARK: - Initialization

    init(screenSize: CGSize, inventory: [Item?], equipment: Equipment) {
        self.inventory = inventory
        self.equipment = equipment

        super.init(screenSize: screenSize)

        setupPanel()
        setupGrids()
        setupItemDetails()
        setupCloseButton()
        setupLabels()

        refreshDisplay()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupPanel() {
        panel = MedievalPanel.large(title: "INVENTORY")
        panel.position = CGPoint(x: 0, y: 0)
        panel.zPosition = Constants.ZPosition.modalContent
        addChild(panel)
    }

    private func setupGrids() {
        // Equipment grid (3x3 for equipment slots)
        equipmentGrid = InventoryGrid(columns: 3, rows: 3, slotSize: 55, spacing: 6)
        equipmentGrid.position = CGPoint(x: -200, y: 80)
        equipmentGrid.onItemSelected = { [weak self] item, index in
            self?.showItemDetails(item)
        }
        panel.addContent(equipmentGrid)

        // Backpack grid (5x6 = 30 slots)
        backpackGrid = InventoryGrid(columns: 5, rows: 6, slotSize: 55, spacing: 6)
        backpackGrid.position = CGPoint(x: 100, y: 80)
        backpackGrid.onItemSelected = { [weak self] item, index in
            self?.showItemDetails(item)
        }
        panel.addContent(backpackGrid)

        // Equipment label
        let equipLabel = MedievalLabel(text: "EQUIPMENT", style: .header, withShadow: true)
        equipLabel.position = CGPoint(x: -200, y: 200)
        panel.addContent(equipLabel)

        // Backpack label
        let backpackLabel = MedievalLabel(text: "BACKPACK", style: .header, withShadow: true)
        backpackLabel.position = CGPoint(x: 100, y: 200)
        panel.addContent(backpackLabel)
    }

    private func setupItemDetails() {
        // Item details panel at bottom
        itemDetailsPanel = MedievalPanel(size: CGSize(width: 600, height: 100))
        itemDetailsPanel.position = CGPoint(x: 0, y: -220)
        panel.addContent(itemDetailsPanel)

        // Item name
        itemNameLabel = MedievalLabel(text: "Select an item", style: .header, withShadow: true, color: UITheme.textGold)
        itemNameLabel.position = CGPoint(x: 0, y: 30)
        itemDetailsPanel.addContent(itemNameLabel)

        // Item description
        itemDescLabel = MedievalLabel(text: "", style: .small, withShadow: false, color: UITheme.textDark)
        itemDescLabel.position = CGPoint(x: 0, y: 5)
        itemDetailsPanel.addContent(itemDescLabel)

        // Item stats
        itemStatsLabel = MedievalLabel(text: "", style: .body, withShadow: false, color: UITheme.forestGreen)
        itemStatsLabel.position = CGPoint(x: 0, y: -20)
        itemDetailsPanel.addContent(itemStatsLabel)
    }

    private func setupLabels() {
        // Capacity indicator
        capacityLabel = MedievalLabel(text: "0/30", style: .small, withShadow: false, color: UITheme.textGray)
        capacityLabel.position = CGPoint(x: 100, y: -150)
        panel.addContent(capacityLabel)
    }

    private func setupCloseButton() {
        closeButton = MedievalButton.small(text: "CLOSE")
        closeButton.position = CGPoint(x: 250, y: -250)
        closeButton.onTap = { [weak self] in
            self?.onClose?()
            self?.dismiss(animated: true)
        }
        panel.addContent(closeButton)
    }

    // MARK: - Display

    private func refreshDisplay() {
        // Convert equipment to array for grid display
        let equipmentItems: [Item?] = [
            equipment.helmet,
            equipment.armor,
            equipment.weapon,
            equipment.ring1,
            equipment.boots,
            equipment.ring2,
            nil, // empty slot
            equipment.amulet,
            nil  // empty slot
        ]

        equipmentGrid.setItems(equipmentItems)
        backpackGrid.setItems(inventory)

        // Update capacity label
        let itemCount = inventory.filter { $0 != nil }.count
        capacityLabel.text = "Items: \(itemCount)/\(backpackGrid.capacity)"
    }

    private func showItemDetails(_ item: Item?) {
        guard let item = item else {
            itemNameLabel.text = "Select an item"
            itemDescLabel.text = ""
            itemStatsLabel.text = ""
            return
        }

        itemNameLabel.text = item.name
        itemNameLabel.fontColor = item.rarity.color

        itemDescLabel.text = item.description

        itemStatsLabel.text = item.statsDescription
    }

    // MARK: - Public Methods

    /// Update inventory data (call before showing screen)
    func updateData(inventory: [Item?], equipment: Equipment) {
        self.inventory = inventory
        self.equipment = equipment
        refreshDisplay()
    }
}
