import SpriteKit

/// A single chunk of the infinite world. Each chunk is chunkSize x chunkSize tiles.
/// Chunks generate their terrain deterministically from their coordinate + world seed.
final class Chunk {
    let coord: ChunkCoord
    let biome: Biome
    let rooms: [Room]
    let structures: [Structure]
    private(set) var tiles: [[TileType]]
    private(set) var elevation: [[Int]]
    let node: SKNode
    var spawnedEnemies = false
    var spawnedItems = false

    init(coord: ChunkCoord, noise: PerlinNoise, moistureNoise: PerlinNoise) {
        self.coord = coord
        self.node = SKNode()
        node.name = "chunk_\(coord.x)_\(coord.y)"

        let size = Constants.chunkSize
        tiles = Array(repeating: Array(repeating: TileType.grass, count: size), count: size)
        elevation = Array(repeating: Array(repeating: 0, count: size), count: size)

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

        // Generate elevation before structures
        generateElevation(noise: noise)

        // Generate structures (non-dungeon chunks)
        if !hasDungeon {
            structures = StructureGenerator.generateStructures(
                seed: coord.chunkSeed,
                biome: biome,
                elevation: elevation,
                existingRooms: rooms
            )
        } else {
            structures = []
        }

        // Apply structures to tile grid before generating terrain
        applyStructures()

        generateTerrain(noise: noise, moistureNoise: moistureNoise, rng: &rng)
        buildNodes()
    }

    // MARK: - Terrain Generation

    private func generateElevation(noise: PerlinNoise) {
        let size = Constants.chunkSize

        for row in 0..<size {
            for col in 0..<size {
                let worldCol = coord.worldOriginCol + col
                let worldRow = coord.worldOriginRow + row

                // Use different noise frequency for elevation (0.03 scale, 5 octaves)
                let nx = CGFloat(worldCol) * 0.03
                let ny = CGFloat(worldRow) * 0.03
                let heightNoise = noise.fractal(x: nx, y: ny, octaves: 5)

                // Map noise (-1 to 1) to biome-specific elevation ranges
                elevation[row][col] = elevationFromNoise(heightNoise)
            }
        }
    }

    private func elevationFromNoise(_ noise: CGFloat) -> Int {
        // Map -1...1 to 0...1
        let normalized = (noise + 1) / 2

        switch biome {
        case .forest:
            // Rolling hills: 30-80
            return 30 + Int(normalized * 50)
        case .desert:
            // Dunes and plateaus: 40-100
            return 40 + Int(normalized * 60)
        case .swamp:
            // Low wetlands: 10-40
            return 10 + Int(normalized * 30)
        case .snow:
            // Mountainous: 100-200
            return 100 + Int(normalized * 100)
        case .dungeon:
            // Flat underground: 50
            return 50
        }
    }

    private func applyStructures() {
        for structure in structures {
            applyStructure(structure)
        }
    }

    private func applyStructure(_ structure: Structure) {
        let template = structure.template
        for row in 0..<template.size.height {
            for col in 0..<template.size.width {
                let tileRow = structure.y + row
                let tileCol = structure.x + col

                guard tileRow >= 0, tileRow < Constants.chunkSize,
                      tileCol >= 0, tileCol < Constants.chunkSize else { continue }

                // Apply rotated footprint
                let footprintTile = getRotatedTile(
                    from: template.footprint,
                    row: row, col: col,
                    rotation: structure.rotation
                )
                tiles[tileRow][tileCol] = footprintTile

                // Apply elevation profile if exists
                if let elevProfile = template.elevationProfile {
                    let elevOffset = getRotatedElevation(
                        from: elevProfile,
                        row: row, col: col,
                        rotation: structure.rotation
                    )
                    elevation[tileRow][tileCol] += elevOffset
                }
            }
        }
    }

    private func getRotatedTile(
        from footprint: [[TileType]],
        row: Int, col: Int,
        rotation: Int
    ) -> TileType {
        let height = footprint.count
        let width = footprint[0].count

        switch rotation {
        case 0:
            return footprint[row][col]
        case 90:
            // (row, col) -> (col, height-1-row)
            let newRow = col
            let newCol = height - 1 - row
            return footprint[newRow][newCol]
        case 180:
            // (row, col) -> (height-1-row, width-1-col)
            let newRow = height - 1 - row
            let newCol = width - 1 - col
            return footprint[newRow][newCol]
        case 270:
            // (row, col) -> (width-1-col, row)
            let newRow = width - 1 - col
            let newCol = row
            return footprint[newRow][newCol]
        default:
            return footprint[row][col]
        }
    }

    private func getRotatedElevation(
        from elevProfile: [[Int]],
        row: Int, col: Int,
        rotation: Int
    ) -> Int {
        let height = elevProfile.count
        let width = elevProfile[0].count

        switch rotation {
        case 0:
            return elevProfile[row][col]
        case 90:
            let newRow = col
            let newCol = height - 1 - row
            return elevProfile[newRow][newCol]
        case 180:
            let newRow = height - 1 - row
            let newCol = width - 1 - col
            return elevProfile[newRow][newCol]
        case 270:
            let newRow = width - 1 - col
            let newCol = row
            return elevProfile[newRow][newCol]
        default:
            return elevProfile[row][col]
        }
    }

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
                let elev = elevation[row][col]
                let globalCol = coord.worldOriginCol + col
                let globalRow = coord.worldOriginRow + row
                let tileNode = createDiamondNode(tile: tile)
                tileNode.position = IsometricMath.gridToScreen(col: globalCol, row: globalRow, elevation: elev)
                // Include elevation in zPosition for proper depth sorting
                tileNode.zPosition = Constants.ZPosition.tile + CGFloat(globalRow + globalCol) * 0.001 + CGFloat(elev) * 0.0001
                node.addChild(tileNode)

                // Add cliff faces for significant elevation changes
                addCliffFaces(row: row, col: col, globalRow: globalRow, globalCol: globalCol, to: tileNode)
            }
        }
    }

    private func addCliffFaces(row: Int, col: Int, globalRow: Int, globalCol: Int, to tileNode: SKNode) {
        let elev = elevation[row][col]
        let size = Constants.chunkSize

        // Check right neighbor (col + 1)
        if col + 1 < size {
            let neighborElev = elevation[row][col + 1]
            if elev - neighborElev >= Constants.cliffThreshold {
                let cliff = createCliffFace(height: elev - neighborElev, direction: .right)
                cliff.zPosition = 0.05
                tileNode.addChild(cliff)
            }
        }

        // Check bottom neighbor (row + 1)
        if row + 1 < size {
            let neighborElev = elevation[row + 1][col]
            if elev - neighborElev >= Constants.cliffThreshold {
                let cliff = createCliffFace(height: elev - neighborElev, direction: .bottom)
                cliff.zPosition = 0.05
                tileNode.addChild(cliff)
            }
        }

        // Check left neighbor (col - 1)
        if col - 1 >= 0 {
            let neighborElev = elevation[row][col - 1]
            if elev - neighborElev >= Constants.cliffThreshold {
                let cliff = createCliffFace(height: elev - neighborElev, direction: .left)
                cliff.zPosition = 0.05
                tileNode.addChild(cliff)
            }
        }

        // Check top neighbor (row - 1)
        if row - 1 >= 0 {
            let neighborElev = elevation[row - 1][col]
            if elev - neighborElev >= Constants.cliffThreshold {
                let cliff = createCliffFace(height: elev - neighborElev, direction: .top)
                cliff.zPosition = 0.05
                tileNode.addChild(cliff)
            }
        }
    }

    private enum CliffDirection {
        case right, bottom, left, top
    }

    private func createCliffFace(height: Int, direction: CliffDirection) -> SKShapeNode {
        let w = Constants.tileWidth / 2
        let h = Constants.tileHeight / 2
        let verticalHeight = CGFloat(height) * Constants.elevationHeightMultiplier

        let path = CGMutablePath()

        // Create vertical face based on direction
        switch direction {
        case .right:
            // Right edge of tile
            path.move(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -h))
            path.addLine(to: CGPoint(x: 0, y: -h - verticalHeight))
            path.addLine(to: CGPoint(x: w, y: -verticalHeight))
            path.closeSubpath()
        case .bottom:
            // Bottom edge of tile
            path.move(to: CGPoint(x: 0, y: -h))
            path.addLine(to: CGPoint(x: -w, y: 0))
            path.addLine(to: CGPoint(x: -w, y: -verticalHeight))
            path.addLine(to: CGPoint(x: 0, y: -h - verticalHeight))
            path.closeSubpath()
        case .left:
            // Left edge of tile
            path.move(to: CGPoint(x: -w, y: 0))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: 0, y: h - verticalHeight))
            path.addLine(to: CGPoint(x: -w, y: -verticalHeight))
            path.closeSubpath()
        case .top:
            // Top edge of tile
            path.move(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w, y: -verticalHeight))
            path.addLine(to: CGPoint(x: 0, y: h - verticalHeight))
            path.closeSubpath()
        }

        let cliffNode = SKShapeNode(path: path)
        // Darker shade for cliff faces
        let baseColor = tiles[0][0].color(biome: biome)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        baseColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let cliffColor = SKColor(red: r * 0.7, green: g * 0.7, blue: b * 0.7, alpha: a)
        let strokeColor = SKColor(red: r * 0.6, green: g * 0.6, blue: b * 0.6, alpha: a)
        cliffNode.fillColor = cliffColor
        cliffNode.strokeColor = strokeColor
        cliffNode.lineWidth = 0.5

        return cliffNode
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

    func elevationAt(localCol: Int, localRow: Int) -> Int? {
        guard localCol >= 0, localCol < Constants.chunkSize,
              localRow >= 0, localRow < Constants.chunkSize else { return nil }
        return elevation[localRow][localCol]
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
