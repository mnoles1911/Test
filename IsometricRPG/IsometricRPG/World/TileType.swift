import SpriteKit

enum TileType: Int {
    case grass = 0
    case dirt = 1
    case stone = 2
    case water = 3
    case wall = 4

    var color: SKColor {
        switch self {
        case .grass: return SKColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1)
        case .dirt:  return SKColor(red: 0.6, green: 0.45, blue: 0.25, alpha: 1)
        case .stone: return SKColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 1)
        case .water: return SKColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.8)
        case .wall:  return SKColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1)
        }
    }

    var isWalkable: Bool {
        switch self {
        case .water, .wall: return false
        default: return true
        }
    }
}
