/// Identifies a chunk in the infinite grid. Hashable so we can use it as a dictionary key.
struct ChunkCoord: Hashable, Equatable {
    let x: Int
    let y: Int

    /// The world-space origin (top-left tile) of this chunk.
    var worldOriginCol: Int { x * Constants.chunkSize }
    var worldOriginRow: Int { y * Constants.chunkSize }

    /// Deterministic seed for this chunk derived from world seed + position.
    var chunkSeed: UInt64 {
        var seed = Constants.worldSeed
        seed ^= UInt64(bitPattern: Int64(x)) &* 0x517CC1B727220A95
        seed ^= UInt64(bitPattern: Int64(y)) &* 0x6C62272E07BB0142
        seed ^= seed >> 33
        seed &*= 0xFF51AFD7ED558CCD
        seed ^= seed >> 33
        return seed
    }

    /// Manhattan distance to another coord.
    func distance(to other: ChunkCoord) -> Int {
        return abs(x - other.x) + abs(y - other.y)
    }

    /// Chebyshev distance (max of axis distances).
    func chebyshevDistance(to other: ChunkCoord) -> Int {
        return max(abs(x - other.x), abs(y - other.y))
    }

    /// Which chunk contains the given world position.
    static func containing(worldCol: Int, worldRow: Int) -> ChunkCoord {
        // Use floor division to handle negative coordinates
        let cx = worldCol >= 0 ? worldCol / Constants.chunkSize : (worldCol - Constants.chunkSize + 1) / Constants.chunkSize
        let cy = worldRow >= 0 ? worldRow / Constants.chunkSize : (worldRow - Constants.chunkSize + 1) / Constants.chunkSize
        return ChunkCoord(x: cx, y: cy)
    }

    static func containing(worldPosition: CGPoint) -> ChunkCoord {
        return containing(worldCol: Int(floor(worldPosition.x)),
                         worldRow: Int(floor(worldPosition.y)))
    }
}
