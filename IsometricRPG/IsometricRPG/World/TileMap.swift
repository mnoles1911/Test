import SpriteKit

/// Manages the isometric tile map grid and its visual representation.
final class TileMap {
    let columns: Int
    let rows: Int
    private(set) var tiles: [[TileType]]
    let rootNode = SKNode()

    init(columns: Int = Constants.mapColumns, rows: Int = Constants.mapRows) {
        self.columns = columns
        self.rows = rows
        self.tiles = Array(repeating: Array(repeating: .grass, count: columns), count: rows)
        generateMap()
        buildNodes()
    }

    // MARK: - Map Generation

    private func generateMap() {
        // Border walls
        for col in 0..<columns {
            tiles[0][col] = .wall
            tiles[rows - 1][col] = .wall
        }
        for row in 0..<rows {
            tiles[row][0] = .wall
            tiles[row][columns - 1] = .wall
        }

        // Scatter some terrain variety
        let seed = UInt64(42)
        var rng = SeededRNG(seed: seed)
        for row in 2..<(rows - 2) {
            for col in 2..<(columns - 2) {
                let roll = rng.nextFloat()
                if roll < 0.08 {
                    tiles[row][col] = .water
                } else if roll < 0.15 {
                    tiles[row][col] = .dirt
                } else if roll < 0.20 {
                    tiles[row][col] = .stone
                } else if roll < 0.24 {
                    tiles[row][col] = .wall
                }
            }
        }

        // Clear spawn area around center
        let cx = columns / 2
        let cy = rows / 2
        for row in (cy - 2)...(cy + 2) {
            for col in (cx - 2)...(cx + 2) {
                tiles[row][col] = .grass
            }
        }
    }

    // MARK: - Visual Construction

    private func buildNodes() {
        rootNode.name = "tileMap"
        for row in 0..<rows {
            for col in 0..<columns {
                let tile = tiles[row][col]
                let node = createDiamondNode(tile: tile)
                node.position = IsometricMath.gridToScreen(col: col, row: row)
                // Sort by row+col so tiles layer correctly
                node.zPosition = Constants.ZPosition.tile + CGFloat(row + col) * 0.01
                node.name = "tile_\(col)_\(row)"
                rootNode.addChild(node)
            }
        }
    }

    private func createDiamondNode(tile: TileType) -> SKShapeNode {
        let w = Constants.tileWidth / 2
        let h = Constants.tileHeight / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -h))
        path.addLine(to: CGPoint(x: -w, y: 0))
        path.closeSubpath()

        let node = SKShapeNode(path: path)
        node.fillColor = tile.color
        node.strokeColor = tile.color.withAlphaComponent(0.4)
        node.lineWidth = 0.5

        // Walls get a raised look
        if tile == .wall {
            let topOffset: CGFloat = 8
            let topPath = CGMutablePath()
            topPath.move(to: CGPoint(x: 0, y: h + topOffset))
            topPath.addLine(to: CGPoint(x: w, y: topOffset))
            topPath.addLine(to: CGPoint(x: 0, y: -h + topOffset))
            topPath.addLine(to: CGPoint(x: -w, y: topOffset))
            topPath.closeSubpath()

            let topNode = SKShapeNode(path: topPath)
            topNode.fillColor = SKColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            topNode.strokeColor = SKColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)
            topNode.lineWidth = 0.5
            topNode.zPosition = 0.1
            node.addChild(topNode)
        }

        return node
    }

    // MARK: - Queries

    func tileAt(col: Int, row: Int) -> TileType? {
        guard col >= 0, col < columns, row >= 0, row < rows else { return nil }
        return tiles[row][col]
    }

    func isWalkable(col: Int, row: Int) -> Bool {
        return tileAt(col: col, row: row)?.isWalkable ?? false
    }

    func isWalkable(worldPosition: CGPoint) -> Bool {
        let col = Int(worldPosition.x.rounded())
        let row = Int(worldPosition.y.rounded())
        return isWalkable(col: col, row: row)
    }
}

// MARK: - Simple Seeded RNG

struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextFloat() -> Float {
        return Float(next() % 1000) / 1000.0
    }
}
