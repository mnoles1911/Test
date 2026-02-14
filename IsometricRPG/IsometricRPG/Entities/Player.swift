import SpriteKit

final class Player: Entity {
    var moveDirection: CGPoint = .zero
    var aimDirection: CGPoint = .zero
    var isShooting: Bool = false
    private var lastFireTime: TimeInterval = 0

    // RPG stats
    var level: Int = 1
    var experience: Int = 0
    var experienceToNext: Int = 100

    // Inventory & Equipment (Phase 3)
    var inventory: [Item?] = []
    var equipment: Equipment = Equipment()

    // Base stats
    private let baseAttack: Int = 10
    private let baseDefense: Int = 5

    // Computed stats (include equipment bonuses)
    var totalAttack: Int {
        return baseAttack + equipment.totalAttackBonus
    }

    var totalDefense: Int {
        return baseDefense + equipment.totalDefenseBonus
    }

    init(worldPosition: CGPoint) {
        let node = Player.createPlayerNode()
        super.init(worldPosition: worldPosition, health: Constants.playerMaxHealth, node: node)
        node.zPosition = Constants.ZPosition.entity
        node.name = "player"
    }

    private static func createPlayerNode() -> SKNode {
        let container = SKNode()

        // Body
        let body = SKShapeNode(rectOf: Constants.playerSize, cornerRadius: 3)
        body.fillColor = SKColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        body.strokeColor = SKColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 1)
        body.lineWidth = 1.5
        container.addChild(body)

        // Direction indicator (small triangle showing aim)
        let indicator = SKShapeNode(circleOfRadius: 3)
        indicator.fillColor = .white
        indicator.strokeColor = .clear
        indicator.position = CGPoint(x: 0, y: Constants.playerSize.height / 2 + 4)
        indicator.name = "aimIndicator"
        container.addChild(indicator)

        // Shadow
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 18, height: 8))
        shadow.fillColor = SKColor.black.withAlphaComponent(0.3)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -Constants.playerSize.height / 2)
        shadow.zPosition = Constants.ZPosition.shadow - Constants.ZPosition.entity
        container.addChild(shadow)

        return container
    }

    override func update(deltaTime: TimeInterval) {
        // Movement
        if moveDirection != .zero {
            let speed = Constants.playerSpeed * CGFloat(deltaTime)
            let newPos = CGPoint(
                x: worldPosition.x + moveDirection.x * speed / Constants.tileWidth,
                y: worldPosition.y + moveDirection.y * speed / Constants.tileHeight
            )
            worldPosition = newPos
        }

        // Update aim indicator rotation
        if aimDirection != .zero {
            let angle = atan2(aimDirection.y, aimDirection.x) - .pi / 2
            if let indicator = node.childNode(withName: "aimIndicator") {
                let radius: CGFloat = Constants.playerSize.height / 2 + 4
                indicator.position = CGPoint(
                    x: cos(angle + .pi / 2) * radius,
                    y: sin(angle + .pi / 2) * radius
                )
            }
        }

        // Depth sorting — entities further "down" the iso grid render on top
        node.zPosition = Constants.ZPosition.entity + (worldPosition.x + worldPosition.y) * 0.01

        super.update(deltaTime: deltaTime)
    }

    func canFire(currentTime: TimeInterval) -> Bool {
        return isShooting && aimDirection != .zero && (currentTime - lastFireTime) >= Constants.fireRate
    }

    func didFire(at time: TimeInterval) {
        lastFireTime = time
    }

    func gainExperience(_ amount: Int) {
        experience += amount
        if experience >= experienceToNext {
            levelUp()
        }
    }

    private func levelUp() {
        level += 1
        experience -= experienceToNext
        experienceToNext = Int(Double(experienceToNext) * 1.5)
        maxHealth += 10
        health = maxHealth

        // Level-up visual
        let label = SKLabelNode(text: "LEVEL UP!")
        label.fontName = "Helvetica-Bold"
        label.fontSize = 14
        label.fontColor = .yellow
        label.position = CGPoint(x: 0, y: 30)
        label.zPosition = 50
        node.addChild(label)

        let rise = SKAction.moveBy(x: 0, y: 20, duration: 1.0)
        let fade = SKAction.fadeOut(withDuration: 1.0)
        label.run(SKAction.sequence([SKAction.group([rise, fade]), SKAction.removeFromParent()]))
    }

    // MARK: - Inventory Management

    /// Add item to inventory
    /// Returns true if successful, false if inventory is full
    func addToInventory(_ item: Item) -> Bool {
        // Find first empty slot
        if let emptyIndex = inventory.firstIndex(where: { $0 == nil }) {
            inventory[emptyIndex] = item
            return true
        }

        // If no empty slots, try to append (up to max capacity)
        if inventory.count < 30 { // Max inventory size
            inventory.append(item)
            return true
        }

        return false // Inventory full
    }

    /// Remove item from inventory at index
    func removeFromInventory(at index: Int) -> Item? {
        guard index >= 0 && index < inventory.count else { return nil }
        let item = inventory[index]
        inventory[index] = nil
        return item
    }

    /// Equip an item (moves from inventory to equipment)
    func equipItem(at inventoryIndex: Int) -> Bool {
        guard let item = inventory[inventoryIndex], item.isEquippable else {
            return false
        }

        // Equip the item (this may return a previously equipped item)
        if let unequippedItem = equipment.equip(item) {
            // Put the unequipped item back in inventory
            inventory[inventoryIndex] = unequippedItem
        } else {
            // No item was replaced, remove from inventory
            inventory[inventoryIndex] = nil
        }

        return true
    }

    /// Unequip an item (moves from equipment to inventory)
    func unequipItem(slot: Equipment.EquipmentSlot) -> Bool {
        guard let item = equipment.unequip(slot: slot) else {
            return false
        }

        // Try to add to inventory
        return addToInventory(item)
    }
}
