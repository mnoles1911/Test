import SpriteKit

/// A single chunk of the infinite world. Each chunk is chunkSize x chunkSize tiles.
/// Chunks generate their terrain deterministically from their coordinate + world seed.
final class Chunk {
    let coord: ChunkCoord
    let biome: Biome
    let rooms: [Room]
    private(set) var tiles: [[TileType]]
    let node: SKNode
    var spawnedEnemies = false
    var spawnedItems = false

    init(coord: ChunkCoord, noise: PerlinNoise, moistureNoise: PerlinNoise) {
        self.coord = coord
        self.node = SKNode()
        node.name = "chunk_\(coord.x)_\(coord.y)"

        let size = Constants.chunkSize
        tiles = Array(repeating: Array(repeating: TileType.grass, count: size), count: size)

        // Determine biome from noise at chunk center
        let centerWorldX = CGFloat(coord.worldOriginCol + size / 2) * 0.02
        let centerWorldY = CGFloat(coord.worldOriginRow + size / 2) * 0.02
        let elevation = noise.fractal(x: centerWorldX, y: centerWorldY, octaves: 3)
        let moisture = moistureNoise.fractal(x: centerWorldX, y: centerWorldY, octaves: 3)
        self.biome = Biome.from(elevation: elevation, moisture: moisture)

        // Generate rooms for dungeon biomes (and occasional rooms elsewhere)
        var rng = SeededRNG(seed: coord.chunkSeed)
        let hasDungeon = biome == .dungeon || rng.nextFloat() < 0.15
        if hasDungeon {
            rooms = DungeonGenerator.generateRooms(seed: coord.chunkSeed)
        } else {
            rooms = []
        }

        generateTerrain(noise: noise, moistureNoise: moistureNoise, rng: &rng)
        buildNodes()
    }

    // MARK: - Terrain Generation

    private func generateTerrain(noise: PerlinNoise, moistureNoise: PerlinNoise, rng: inout SeededRNG) {
        let size = Constants.chunkSize

        if !rooms.isEmpty {
            // Dungeon chunk: fill with dungeon wall, then carve rooms
            for row in 0..<size {
                for col in 0..<size {
                    tiles[row][col] = .dungeonWall
                }
            }
            DungeonGenerator.carve(rooms: rooms, into: &tiles)
        } else {
            // Open-world chunk: use noise for natural terrain
            for row in 0..<size {
                for col in 0..<size {
                    let worldCol = coord.worldOriginCol + col
                    let worldRow = coord.worldOriginRow + row
                    let nx = CGFloat(worldCol) * 0.08
                    let ny = CGFloat(worldRow) * 0.08
                    let n = noise.fractal(x: nx, y: ny, octaves: 4)
                    let m = moistureNoise.fractal(x: nx * 0.5, y: ny * 0.5, octaves: 3)

                    tiles[row][col] = tileFor(noise: n, moisture: m, rng: &rng)
                }
            }
        }
    }

    private func tileFor(noise n: CGFloat, moisture m: CGFloat, rng: inout SeededRNG) -> TileType {
        switch biome {
        case .forest:
            if n < -0.35 { return .water }
            if n < -0.15 { return .dirt }
            if rng.nextFloat() < 0.05 { return .stone }
            return .grass

        case .desert:
            if n < -0.4 { return .water }
            if n > 0.3 { return .stone }
            if rng.nextFloat() < 0.08 { return .dirt }
            return .sand

        case .dungeon:
            return .grass // shouldn't reach here for dungeon chunks with rooms

        case .swamp:
            if n < -0.1 { return .water }
            if n < 0.1 { return .swamp }
            if rng.nextFloat() < 0.1 { return .dirt }
            return .grass

        case .snow:
            if n < -0.3 { return .water }
            if n > 0.35 { return .stone }
            if rng.nextFloat() < 0.06 { return .dirt }
            return .snow
        }
    }

    // MARK: - Rendering

    private func buildNodes() {
        let size = Constants.chunkSize
        for row in 0..<size {
            for col in 0..<size {
                let tile = tiles[row][col]
                let globalCol = coord.worldOriginCol + col
                let globalRow = coord.worldOriginRow + row
                let tileNode = createDiamondNode(tile: tile)
                tileNode.position = IsometricMath.gridToScreen(col: globalCol, row: globalRow)
                tileNode.zPosition = Constants.ZPosition.tile + CGFloat(globalRow + globalCol) * 0.001
                node.addChild(tileNode)
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

        let tileNode = SKShapeNode(path: path)
        tileNode.fillColor = tile.color(biome: biome)
        tileNode.strokeColor = tile.color(biome: biome).withAlphaComponent(0.3)
        tileNode.lineWidth = 0.5

        // Walls / dungeon walls get height
        if tile == .wall || tile == .dungeonWall {
            let topOffset: CGFloat = tile == .dungeonWall ? 10 : 8
            let topPath = CGMutablePath()
            topPath.move(to: CGPoint(x: 0, y: h + topOffset))
            topPath.addLine(to: CGPoint(x: w, y: topOffset))
            topPath.addLine(to: CGPoint(x: 0, y: -h + topOffset))
            topPath.addLine(to: CGPoint(x: -w, y: topOffset))
            topPath.closeSubpath()

            let topNode = SKShapeNode(path: topPath)
            let wallColor = tile == .dungeonWall
                ? SKColor(red: 0.3, green: 0.28, blue: 0.35, alpha: 1)
                : SKColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            topNode.fillColor = wallColor
            topNode.strokeColor = wallColor.withAlphaComponent(0.6)
            topNode.lineWidth = 0.5
            topNode.zPosition = 0.1
            tileNode.addChild(topNode)
        }

        return tileNode
    }

    // MARK: - Queries

    func tileAt(localCol: Int, localRow: Int) -> TileType? {
        guard localCol >= 0, localCol < Constants.chunkSize,
              localRow >= 0, localRow < Constants.chunkSize else { return nil }
        return tiles[localRow][localCol]
    }

    /// Get walkable positions inside rooms (for spawning entities/items).
    func walkableRoomPositions() -> [(worldCol: Int, worldRow: Int)] {
        var positions: [(Int, Int)] = []
        for room in rooms {
            for row in (room.y + 1)..<(room.y + room.height - 1) {
                for col in (room.x + 1)..<(room.x + room.width - 1) {
                    guard row >= 0, row < Constants.chunkSize,
                          col >= 0, col < Constants.chunkSize,
                          tiles[row][col].isWalkable else { continue }
                    positions.append((coord.worldOriginCol + col, coord.worldOriginRow + row))
                }
            }
        }
        return positions
    }

    /// Get all walkable positions in this chunk.
    func walkablePositions() -> [(worldCol: Int, worldRow: Int)] {
        var positions: [(Int, Int)] = []
        for row in 0..<Constants.chunkSize {
            for col in 0..<Constants.chunkSize {
                if tiles[row][col].isWalkable {
                    positions.append((coord.worldOriginCol + col, coord.worldOriginRow + row))
                }
            }
        }
        return positions
    }
}
