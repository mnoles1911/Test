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

    private weak var worldManager: WorldManager?

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

    /// Set the world manager reference for rendering terrain
    func setWorldManager(_ worldManager: WorldManager) {
        self.worldManager = worldManager
    }

    // MARK: - Rendering

    // MARK: - Update

    /// Update minimap with current game state
    func update(playerPosition: CGPoint, enemies: [Enemy], currentTime: TimeInterval) {
        // Throttle updates for performance
        guard currentTime - lastUpdateTime > updateInterval else { return }
        lastUpdateTime = currentTime

        // Player is always at center of minimap
        playerDot.position = .zero

        // Update enemy dots relative to player
        updateEnemyDots(enemies: enemies, playerPosition: playerPosition)

        // Refresh terrain around player
        renderTerrain(aroundPlayer: playerPosition)
    }

    private func updateEnemyDots(enemies: [Enemy], playerPosition: CGPoint) {
        // Remove old enemy dots
        for dot in enemyDots {
            dot.removeFromParent()
        }
        enemyDots.removeAll()

        // Create new enemy dots relative to player
        for enemy in enemies where enemy.isAlive {
            let dot = SKShapeNode(circleOfRadius: 3)
            dot.fillColor = UITheme.crimson
            dot.strokeColor = .clear
            dot.position = worldToMinimapPosition(enemy.worldPosition, relativeTo: playerPosition)
            dot.zPosition = 5
            contentNode.addChild(dot)
            enemyDots.append(dot)
        }
    }

    private func renderTerrain(aroundPlayer playerPosition: CGPoint) {
        guard let worldManager = worldManager else { return }

        // Remove existing terrain nodes
        contentNode.enumerateChildNodes(withName: "terrain_*") { node, _ in
            node.removeFromParent()
        }

        // Render only chunks near player (within minimap view range)
        let viewRange: CGFloat = 10 // tiles in each direction
        let minX = Int(playerPosition.x - viewRange)
        let maxX = Int(playerPosition.x + viewRange)
        let minY = Int(playerPosition.y - viewRange)
        let maxY = Int(playerPosition.y + viewRange)

        for (_, chunk) in worldManager.loadedChunks {
            let chunkMinX = chunk.coord.col * Constants.chunkSize
            let chunkMaxX = chunkMinX + Constants.chunkSize
            let chunkMinY = chunk.coord.row * Constants.chunkSize
            let chunkMaxY = chunkMinY + Constants.chunkSize

            // Skip chunks outside view range
            if chunkMaxX < minX || chunkMinX > maxX || chunkMaxY < minY || chunkMinY > maxY {
                continue
            }

            for row in 0..<Constants.chunkSize {
                for col in 0..<Constants.chunkSize {
                    let tile = chunk.tiles[row][col]
                    if tile == .wall {
                        let worldCol = chunk.coord.col * Constants.chunkSize + col
                        let worldRow = chunk.coord.row * Constants.chunkSize + row
                        let worldPos = CGPoint(x: CGFloat(worldCol) + 0.5, y: CGFloat(worldRow) + 0.5)
                        let minimapPos = worldToMinimapPosition(worldPos, relativeTo: playerPosition)

                        // Only render if within minimap circle
                        let distance = sqrt(minimapPos.x * minimapPos.x + minimapPos.y * minimapPos.y)
                        if distance < size.width / 2 {
                            let wallDot = SKShapeNode(rectOf: CGSize(width: pixelsPerTile, height: pixelsPerTile))
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
        }
    }

    // MARK: - Coordinate Conversion

    /// Convert world position to minimap position relative to player (player is at center)
    private func worldToMinimapPosition(_ worldPos: CGPoint, relativeTo playerPos: CGPoint) -> CGPoint {
        // Calculate relative position to player
        let relativeX = (worldPos.x - playerPos.x) * pixelsPerTile
        let relativeY = (worldPos.y - playerPos.y) * pixelsPerTile

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
