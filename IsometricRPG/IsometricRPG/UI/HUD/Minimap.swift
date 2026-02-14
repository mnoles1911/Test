import SpriteKit

/// Minimap showing simplified top-down representation of the game world
/// Displays player, enemies, and walls with a medieval compass frame
class Minimap: SKNode {
    // MARK: - Properties

    private let size: CGSize
    private let background: SKShapeNode
    private let frame: SKShapeNode
    private let contentNode: SKCropNode
    private let maskNode: SKShapeNode

    private var playerDot: SKShapeNode!
    private var enemyDots: [SKShapeNode] = []

    private var lastUpdateTime: TimeInterval = 0
    private let updateInterval: TimeInterval = 0.5 // Update every 0.5 seconds for performance

    private weak var tileMap: TileMap?

    // Scale: 1 world tile = pixelsPerTile on minimap
    private let pixelsPerTile: CGFloat = 8

    // MARK: - Initialization

    init(size: CGSize = CGSize(width: 150, height: 150)) {
        self.size = size

        // Background (dark stone)
        background = SKShapeNode(circleOfRadius: size.width / 2)
        background.fillColor = UITheme.darkStone.withAlphaComponent(0.9)
        background.strokeColor = .clear
        background.zPosition = 0

        // Ornamental frame (gold border)
        frame = SKShapeNode(circleOfRadius: size.width / 2)
        frame.fillColor = .clear
        frame.strokeColor = UITheme.gold
        frame.lineWidth = 3
        frame.zPosition = 2

        // Mask for circular clipping
        maskNode = SKShapeNode(circleOfRadius: size.width / 2 - 4)
        maskNode.fillColor = .white
        maskNode.strokeColor = .clear

        // Content node (all map content goes here, clipped by mask)
        contentNode = SKCropNode()
        contentNode.maskNode = maskNode
        contentNode.zPosition = 1

        super.init()

        addChild(background)
        addChild(contentNode)
        addChild(frame)

        setupPlayerDot()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupPlayerDot() {
        // Player represented as gold dot
        playerDot = SKShapeNode(circleOfRadius: 4)
        playerDot.fillColor = UITheme.gold
        playerDot.strokeColor = UITheme.textLight
        playerDot.lineWidth = 1
        playerDot.zPosition = 10
        contentNode.addChild(playerDot)
    }

    /// Set the tile map reference for rendering terrain
    func setTileMap(_ tileMap: TileMap) {
        self.tileMap = tileMap
        renderTerrain()
    }

    // MARK: - Rendering

    private func renderTerrain() {
        guard let tileMap = tileMap else { return }

        // Remove existing terrain nodes
        contentNode.enumerateChildNodes(withName: "terrain_*") { node, _ in
            node.removeFromParent()
        }

        // Render simplified terrain (only walls for now)
        for row in 0..<tileMap.rows {
            for col in 0..<tileMap.columns {
                if let tile = tileMap.tileAt(col: col, row: row), tile == .wall {
                    let dotSize: CGFloat = pixelsPerTile
                    let worldPos = CGPoint(x: CGFloat(col), y: CGFloat(row))
                    let minimapPos = worldToMinimapPosition(worldPos)

                    let wallDot = SKShapeNode(rectOf: CGSize(width: dotSize, height: dotSize))
                    wallDot.fillColor = UITheme.textGray
                    wallDot.strokeColor = .clear
                    wallDot.position = minimapPos
                    wallDot.zPosition = 1
                    wallDot.name = "terrain_wall"
                    contentNode.addChild(wallDot)
                }
            }
        }
    }

    // MARK: - Update

    /// Update minimap with current game state
    func update(playerPosition: CGPoint, enemies: [Enemy], currentTime: TimeInterval) {
        // Throttle updates for performance
        guard currentTime - lastUpdateTime > updateInterval else { return }
        lastUpdateTime = currentTime

        // Update player position
        playerDot.position = worldToMinimapPosition(playerPosition)

        // Update enemy dots
        updateEnemyDots(enemies: enemies)
    }

    private func updateEnemyDots(enemies: [Enemy]) {
        // Remove old enemy dots
        for dot in enemyDots {
            dot.removeFromParent()
        }
        enemyDots.removeAll()

        // Create new enemy dots
        for enemy in enemies where enemy.isAlive {
            let dot = SKShapeNode(circleOfRadius: 3)
            dot.fillColor = UITheme.crimson
            dot.strokeColor = .clear
            dot.position = worldToMinimapPosition(enemy.worldPosition)
            dot.zPosition = 5
            contentNode.addChild(dot)
            enemyDots.append(dot)
        }
    }

    // MARK: - Coordinate Conversion

    private func worldToMinimapPosition(_ worldPos: CGPoint) -> CGPoint {
        guard let tileMap = tileMap else { return .zero }

        // Center the map on the player
        // Map world coordinates to minimap coordinates
        let centerCol = CGFloat(tileMap.columns) / 2
        let centerRow = CGFloat(tileMap.rows) / 2

        let relativeX = (worldPos.x - centerCol) * pixelsPerTile
        let relativeY = (worldPos.y - centerRow) * pixelsPerTile

        // Flip Y for top-down view
        return CGPoint(x: relativeX, y: -relativeY)
    }

    // MARK: - Visibility

    func hide() {
        isHidden = true
    }

    func show() {
        isHidden = false
    }
}
