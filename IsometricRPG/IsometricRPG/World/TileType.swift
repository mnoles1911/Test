import SpriteKit

enum Biome: Int, CaseIterable {
    case forest = 0
    case desert = 1
    case dungeon = 2
    case swamp = 3
    case snow = 4

    /// Determines biome from noise values. Elevation and moisture create natural regions.
    static func from(elevation: CGFloat, moisture: CGFloat) -> Biome {
        if elevation < -0.2 { return .swamp }
        if elevation > 0.4 { return .snow }
        if moisture < -0.15 { return .desert }
        if moisture > 0.2 { return .forest }
        return .dungeon
    }
}

enum TileType: Int {
    case grass = 0
    case dirt = 1
    case stone = 2
    case water = 3
    case wall = 4
    case sand = 5
    case snow = 6
    case swamp = 7
    case dungeonFloor = 8
    case dungeonWall = 9
    case corridor = 10
    case doorway = 11

    func color(biome: Biome) -> SKColor {
        switch self {
        case .grass:
            switch biome {
            case .forest: return SKColor(red: 0.2, green: 0.6, blue: 0.2, alpha: 1)
            case .swamp:  return SKColor(red: 0.25, green: 0.45, blue: 0.2, alpha: 1)
            case .snow:   return SKColor(red: 0.7, green: 0.8, blue: 0.7, alpha: 1)
            default:      return SKColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1)
            }
        case .dirt:         return SKColor(red: 0.6, green: 0.45, blue: 0.25, alpha: 1)
        case .stone:        return SKColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 1)
        case .water:        return SKColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.8)
        case .wall:         return SKColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1)
        case .sand:         return SKColor(red: 0.85, green: 0.75, blue: 0.5, alpha: 1)
        case .snow:         return SKColor(red: 0.9, green: 0.92, blue: 0.95, alpha: 1)
        case .swamp:        return SKColor(red: 0.3, green: 0.38, blue: 0.2, alpha: 0.9)
        case .dungeonFloor: return SKColor(red: 0.28, green: 0.25, blue: 0.3, alpha: 1)
        case .dungeonWall:  return SKColor(red: 0.22, green: 0.2, blue: 0.25, alpha: 1)
        case .corridor:     return SKColor(red: 0.32, green: 0.3, blue: 0.28, alpha: 1)
        case .doorway:      return SKColor(red: 0.5, green: 0.4, blue: 0.2, alpha: 1)
        }
    }

    var isWalkable: Bool {
        switch self {
        case .water, .wall, .dungeonWall: return false
        default: return true
        }
    }
}
