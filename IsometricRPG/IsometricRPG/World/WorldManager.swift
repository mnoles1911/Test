import SpriteKit

/// Manages the infinite, chunk-based world. Loads/unloads chunks around the player.
final class WorldManager {
    private(set) var loadedChunks: [ChunkCoord: Chunk] = [:]
    let rootNode = SKNode()
    private let noise: PerlinNoise
    private let moistureNoise: PerlinNoise
    private var lastPlayerChunk: ChunkCoord?

    init() {
        noise = PerlinNoise(seed: Constants.worldSeed)
        moistureNoise = PerlinNoise(seed: Constants.worldSeed &+ 12345)
        rootNode.name = "world"
    }

    // MARK: - Chunk Management

    /// Call every frame with the player's world position.
    /// Returns (loaded, unloaded) chunk coords for this tick.
    @discardableResult
    func updateAroundPlayer(worldPosition: CGPoint) -> (loaded: [ChunkCoord], unloaded: [ChunkCoord]) {
        let playerChunk = ChunkCoord.containing(worldPosition: worldPosition)

        // Skip if player hasn't moved chunks
        if playerChunk == lastPlayerChunk { return ([], []) }
        lastPlayerChunk = playerChunk

        var loaded: [ChunkCoord] = []
        var unloaded: [ChunkCoord] = []

        // Load chunks within radius
        let r = Constants.loadRadius
        for dy in -r...r {
            for dx in -r...r {
                let coord = ChunkCoord(x: playerChunk.x + dx, y: playerChunk.y + dy)
                if loadedChunks[coord] == nil {
                    let chunk = Chunk(coord: coord, noise: noise, moistureNoise: moistureNoise)
                    loadedChunks[coord] = chunk
                    rootNode.addChild(chunk.node)
                    loaded.append(coord)
                }
            }
        }

        // Unload distant chunks
        let toUnload = loadedChunks.keys.filter { coord in
            coord.chebyshevDistance(to: playerChunk) > Constants.unloadRadius
        }
        for coord in toUnload {
            if let chunk = loadedChunks.removeValue(forKey: coord) {
                chunk.node.removeFromParent()
                unloaded.append(coord)
            }
        }

        return (loaded, unloaded)
    }

    /// Force-load chunks around a position (used at game start).
    func initialLoad(around worldPosition: CGPoint) {
        updateAroundPlayer(worldPosition: worldPosition)
    }

    // MARK: - Tile Queries

    func tileAt(worldCol: Int, worldRow: Int) -> TileType? {
        let chunkCoord = ChunkCoord.containing(worldCol: worldCol, worldRow: worldRow)
        guard let chunk = loadedChunks[chunkCoord] else { return nil }
        let localCol = worldCol - chunkCoord.worldOriginCol
        let localRow = worldRow - chunkCoord.worldOriginRow
        return chunk.tileAt(localCol: localCol, localRow: localRow)
    }

    func elevationAt(worldCol: Int, worldRow: Int) -> Int? {
        let chunkCoord = ChunkCoord.containing(worldCol: worldCol, worldRow: worldRow)
        guard let chunk = loadedChunks[chunkCoord] else { return nil }
        let localCol = worldCol - chunkCoord.worldOriginCol
        let localRow = worldRow - chunkCoord.worldOriginRow
        return chunk.elevationAt(localCol: localCol, localRow: localRow)
    }

    func elevationAt(worldPosition: CGPoint) -> Int? {
        let col = Int(floor(worldPosition.x + 0.5))
        let row = Int(floor(worldPosition.y + 0.5))
        return elevationAt(worldCol: col, worldRow: row)
    }

    func isWalkable(worldCol: Int, worldRow: Int) -> Bool {
        return tileAt(worldCol: worldCol, worldRow: worldRow)?.isWalkable ?? false
    }

    func isWalkable(worldPosition: CGPoint) -> Bool {
        let col = Int(floor(worldPosition.x + 0.5))
        let row = Int(floor(worldPosition.y + 0.5))
        return isWalkable(worldCol: col, worldRow: row)
    }

    /// Check if movement from one position to another is walkable (considering elevation).
    func isWalkable(from: CGPoint, to: CGPoint) -> Bool {
        let fromCol = Int(floor(from.x + 0.5))
        let fromRow = Int(floor(from.y + 0.5))
        let toCol = Int(floor(to.x + 0.5))
        let toRow = Int(floor(to.y + 0.5))

        // Check base walkability of destination
        guard let toTile = tileAt(worldCol: toCol, worldRow: toRow),
              toTile.isWalkable else {
            return false
        }

        // Check elevation difference
        guard let fromElev = elevationAt(worldCol: fromCol, worldRow: fromRow),
              let toElev = elevationAt(worldCol: toCol, worldRow: toRow) else {
            return false
        }

        let heightDiff = abs(toElev - fromElev)
        if heightDiff > Constants.maxWalkableElevationDiff {
            return false
        }

        return true
    }

    func biomeAt(worldPosition: CGPoint) -> Biome? {
        let chunkCoord = ChunkCoord.containing(worldPosition: worldPosition)
        return loadedChunks[chunkCoord]?.biome
    }

    func chunkAt(worldPosition: CGPoint) -> Chunk? {
        let coord = ChunkCoord.containing(worldPosition: worldPosition)
        return loadedChunks[coord]
    }

    /// Get newly loaded chunks that haven't had enemies spawned yet.
    func chunksNeedingEnemySpawn() -> [Chunk] {
        return loadedChunks.values.filter { !$0.spawnedEnemies }
    }

    /// Get newly loaded chunks that haven't had items spawned yet.
    func chunksNeedingItemSpawn() -> [Chunk] {
        return loadedChunks.values.filter { !$0.spawnedItems }
    }
}
