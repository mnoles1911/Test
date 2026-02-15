import Foundation

/// Type of structure that can appear in the world
enum StructureType: String, CaseIterable {
    // Buildings
    case house
    case shop
    case inn
    case tower
    case castle
    case ruin

    // Camps
    case banditCamp
    case merchantCamp
    case shrine

    // Environmental
    case tree
    case rock
    case bush
    case log
    case cactus

    // Treasures
    case chest
    case buriedTreasure
    case altar

    // Fortifications
    case wall
    case gate
    case watchtower
}

/// Category of structure for gameplay purposes
enum StructureCategory {
    case building       // Multi-tile structures with interiors
    case camp           // Clustered entities/items
    case decoration     // Single-tile visual elements
    case treasure       // Loot containers
    case fortification  // Defensive structures
}

/// Template defining a reusable structure pattern
struct StructureTemplate {
    let type: StructureType
    let category: StructureCategory
    let size: (width: Int, height: Int)
    let footprint: [[TileType]]          // Tile layout for structure
    let elevationProfile: [[Int]]?       // Optional height map (for multi-level structures)
    let spawnWeight: Float               // Base spawn probability
    let biomes: [Biome]                  // Which biomes this can appear in
    let minElevation: Int?               // Elevation constraints
    let maxElevation: Int?
    let requiresFlat: Bool               // Must be on flat terrain?
    let clusterSize: Int?                // If set, spawns in groups (e.g., villages)
}

/// A placed instance of a structure in the world
struct Structure {
    let template: StructureTemplate
    let x: Int                           // Local chunk coordinates
    let y: Int
    let rotation: Int                    // 0, 90, 180, 270 degrees
    let seed: UInt64                     // For procedural variation within structure

    /// Get the bounds of this structure
    var bounds: (x: Int, y: Int, width: Int, height: Int) {
        return (x: x, y: y, width: template.size.width, height: template.size.height)
    }

    /// Check if this structure overlaps with another structure or room
    func overlaps(_ other: Structure) -> Bool {
        let (ax, ay, aw, ah) = bounds
        let (bx, by, bw, bh) = other.bounds
        return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by
    }

    func overlaps(_ room: Room) -> Bool {
        let (ax, ay, aw, ah) = bounds
        return ax < room.x + room.width && ax + aw > room.x &&
               ay < room.y + room.height && ay + ah > room.y
    }
}
