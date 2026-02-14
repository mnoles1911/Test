import SpriteKit

/// Grid-based inventory display with tap-to-select functionality
/// Future enhancement: Add drag-and-drop support
class InventoryGrid: SKNode {
    // MARK: - Properties

    private let columns: Int
    private let rows: Int
    private let slotSize: CGFloat
    private let spacing: CGFloat

    private var slots: [[SKNode]] = []
    private var items: [Item?] = []

    var selectedIndex: Int?
    var onItemSelected: ((Item?, Int) -> Void)?

    // MARK: - Initialization

    init(columns: Int, rows: Int, slotSize: CGFloat = 60, spacing: CGFloat = 4) {
        self.columns = columns
        self.rows = rows
        self.slotSize = slotSize
        self.spacing = spacing

        super.init()

        // Initialize items array
        items = Array(repeating: nil, count: columns * rows)

        setupGrid()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupGrid() {
        let totalWidth = CGFloat(columns) * (slotSize + spacing) - spacing
        let totalHeight = CGFloat(rows) * (slotSize + spacing) - spacing
        let startX = -totalWidth / 2 + slotSize / 2
        let startY = totalHeight / 2 - slotSize / 2

        for row in 0..<rows {
            var rowSlots: [SKNode] = []

            for col in 0..<columns {
                let slot = createSlot()
                let x = startX + CGFloat(col) * (slotSize + spacing)
                let y = startY - CGFloat(row) * (slotSize + spacing)
                slot.position = CGPoint(x: x, y: y)
                slot.name = "slot_\(row)_\(col)"
                addChild(slot)
                rowSlots.append(slot)
            }

            slots.append(rowSlots)
        }

        isUserInteractionEnabled = true
    }

    private func createSlot() -> SKNode {
        let slotNode = SKNode()

        // Background
        let background = SKShapeNode(rectOf: CGSize(width: slotSize, height: slotSize), cornerRadius: 4)
        background.fillColor = UITheme.darkStone.withAlphaComponent(0.8)
        background.strokeColor = UITheme.parchmentDark
        background.lineWidth = 2
        background.zPosition = 0
        background.name = "background"
        slotNode.addChild(background)

        // Item container (will hold item representation)
        let itemContainer = SKNode()
        itemContainer.name = "itemContainer"
        itemContainer.zPosition = 1
        slotNode.addChild(itemContainer)

        return slotNode
    }

    // MARK: - Item Management

    /// Set items in the grid
    func setItems(_ items: [Item?]) {
        self.items = items

        // Pad with nil if needed
        while self.items.count < columns * rows {
            self.items.append(nil)
        }

        // Truncate if too many
        if self.items.count > columns * rows {
            self.items = Array(self.items.prefix(columns * rows))
        }

        refreshDisplay()
    }

    /// Get item at index
    func getItem(at index: Int) -> Item? {
        guard index >= 0 && index < items.count else { return nil }
        return items[index]
    }

    /// Add item to first empty slot
    func addItem(_ item: Item) -> Bool {
        if let emptyIndex = items.firstIndex(where: { $0 == nil }) {
            items[emptyIndex] = item
            refreshSlot(at: emptyIndex)
            return true
        }
        return false
    }

    /// Remove item at index
    func removeItem(at index: Int) -> Item? {
        guard index >= 0 && index < items.count else { return nil }
        let item = items[index]
        items[index] = nil
        refreshSlot(at: index)
        return item
    }

    // MARK: - Display

    private func refreshDisplay() {
        for index in 0..<items.count {
            refreshSlot(at: index)
        }
    }

    private func refreshSlot(at index: Int) {
        let row = index / columns
        let col = index % columns

        guard row < slots.count && col < slots[row].count else { return }
        let slotNode = slots[row][col]

        // Clear existing item display
        if let itemContainer = slotNode.childNode(withName: "itemContainer") {
            itemContainer.removeAllChildren()

            // Add item representation if present
            if let item = items[index] {
                displayItem(item, in: itemContainer)
            }
        }

        // Update background highlight if selected
        if let background = slotNode.childNode(withName: "background") as? SKShapeNode {
            if selectedIndex == index {
                background.strokeColor = UITheme.gold
                background.lineWidth = 3
            } else {
                background.strokeColor = UITheme.parchmentDark
                background.lineWidth = 2
            }
        }
    }

    private func displayItem(_ item: Item, in container: SKNode) {
        // Simple colored square representing the item
        // In Phase 5, this will be replaced with actual item sprites
        let itemShape = SKShapeNode(rectOf: CGSize(width: slotSize * 0.7, height: slotSize * 0.7), cornerRadius: 4)
        itemShape.fillColor = item.rarity.color.withAlphaComponent(0.6)
        itemShape.strokeColor = item.rarity.color
        itemShape.lineWidth = 2
        container.addChild(itemShape)

        // Item initial (for identification)
        let initial = SKLabelNode(fontNamed: UITheme.headerFont)
        initial.text = String(item.name.prefix(1))
        initial.fontSize = 24
        initial.fontColor = UITheme.textLight
        initial.verticalAlignmentMode = .center
        initial.horizontalAlignmentMode = .center
        container.addChild(initial)
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Find which slot was tapped
        if let index = slotIndex(at: location) {
            selectedIndex = index
            refreshDisplay()

            let item = items[index]
            onItemSelected?(item, index)
        }
    }

    private func slotIndex(at point: CGPoint) -> Int? {
        for row in 0..<rows {
            for col in 0..<columns {
                let slotNode = slots[row][col]
                let slotBounds = slotNode.calculateAccumulatedFrame()

                if slotBounds.contains(point) {
                    return row * columns + col
                }
            }
        }
        return nil
    }

    // MARK: - Capacity

    var capacity: Int {
        return columns * rows
    }

    var itemCount: Int {
        return items.filter { $0 != nil }.count
    }
}
