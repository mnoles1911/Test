import CoreGraphics

/// A rectangular room placed within a chunk during dungeon generation.
struct Room {
    let x: Int      // local to chunk (0..<chunkSize)
    let y: Int
    let width: Int
    let height: Int

    var centerX: Int { x + width / 2 }
    var centerY: Int { y + height / 2 }
    var center: (Int, Int) { (centerX, centerY) }

    func intersects(_ other: Room, padding: Int = 1) -> Bool {
        return x - padding < other.x + other.width &&
               x + width + padding > other.x &&
               y - padding < other.y + other.height &&
               y + height + padding > other.y
    }
}

/// Generates dungeon layouts (rooms + corridors) for individual chunks.
/// Each chunk gets a deterministic layout based on its seed.
enum DungeonGenerator {

    /// Generate a set of rooms for a chunk. Returns rooms in local chunk coordinates.
    static func generateRooms(seed: UInt64, count: Int = Constants.roomsPerChunk) -> [Room] {
        var rng = SeededRNG(seed: seed &+ 0xDEADBEEF)
        var rooms: [Room] = []
        let size = Constants.chunkSize

        for _ in 0..<(count * 3) { // attempt up to 3x to place rooms
            guard rooms.count < count else { break }

            let w = Constants.roomMinSize + Int(rng.next() % UInt64(Constants.roomMaxSize - Constants.roomMinSize + 1))
            let h = Constants.roomMinSize + Int(rng.next() % UInt64(Constants.roomMaxSize - Constants.roomMinSize + 1))
            let rx = 1 + Int(rng.next() % UInt64(max(size - w - 2, 1)))
            let ry = 1 + Int(rng.next() % UInt64(max(size - h - 2, 1)))

            let candidate = Room(x: rx, y: ry, width: w, height: h)
            let overlaps = rooms.contains { $0.intersects(candidate, padding: 1) }
            if !overlaps {
                rooms.append(candidate)
            }
        }

        return rooms
    }

    /// Carve rooms and L-shaped corridors between them into a tile grid.
    /// The grid should already be filled with the base tile (e.g., dungeonWall).
    static func carve(rooms: [Room], into tiles: inout [[TileType]]) {
        // Carve rooms
        for room in rooms {
            for row in room.y..<(room.y + room.height) {
                for col in room.x..<(room.x + room.width) {
                    guard row >= 0, row < tiles.count, col >= 0, col < tiles[0].count else { continue }
                    tiles[row][col] = .dungeonFloor
                }
            }
        }

        // Connect rooms with corridors (each room to the next)
        for i in 0..<(rooms.count - 1) {
            let (ax, ay) = rooms[i].center
            let (bx, by) = rooms[i + 1].center
            carveCorridor(from: (ax, ay), to: (bx, by), into: &tiles)
        }

        // Place doorways at corridor-room transitions
        for room in rooms {
            placeDoorways(room: room, tiles: &tiles)
        }
    }

    private static func carveCorridor(from a: (Int, Int), to b: (Int, Int),
                                       into tiles: inout [[TileType]]) {
        let (ax, ay) = a
        let (bx, by) = b
        let w = Constants.corridorWidth

        // Horizontal leg
        let xRange = ax < bx ? ax...bx : bx...ax
        for col in xRange {
            for offset in 0..<w {
                let row = ay + offset - w / 2
                guard row >= 0, row < tiles.count, col >= 0, col < tiles[0].count else { continue }
                if tiles[row][col] == .dungeonWall {
                    tiles[row][col] = .corridor
                }
            }
        }

        // Vertical leg
        let yRange = ay < by ? ay...by : by...ay
        for row in yRange {
            for offset in 0..<w {
                let col = bx + offset - w / 2
                guard row >= 0, row < tiles.count, col >= 0, col < tiles[0].count else { continue }
                if tiles[row][col] == .dungeonWall {
                    tiles[row][col] = .corridor
                }
            }
        }
    }

    private static func placeDoorways(room: Room, tiles: inout [[TileType]]) {
        let edges = [
            (room.centerX, room.y - 1),          // top
            (room.centerX, room.y + room.height), // bottom
            (room.x - 1, room.centerY),           // left
            (room.x + room.width, room.centerY),  // right
        ]

        for (col, row) in edges {
            guard row >= 0, row < tiles.count, col >= 0, col < tiles[0].count else { continue }
            if tiles[row][col] == .corridor {
                tiles[row][col] = .doorway
            }
        }
    }
}
