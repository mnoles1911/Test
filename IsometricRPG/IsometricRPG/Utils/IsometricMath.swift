import CoreGraphics

/// Utility for converting between Cartesian (game world) and isometric (screen) coordinates.
enum IsometricMath {
    /// Convert a grid position (col, row) to screen-space isometric coordinates.
    static func gridToScreen(col: Int, row: Int) -> CGPoint {
        let x = CGFloat(col - row) * (Constants.tileWidth / 2)
        let y = CGFloat(col + row) * (Constants.tileHeight / 2)
        return CGPoint(x: x, y: -y) // SpriteKit y-up, iso y-down
    }

    /// Convert a world position (continuous) to screen-space isometric coordinates.
    static func worldToScreen(_ point: CGPoint) -> CGPoint {
        let x = (point.x - point.y) * (Constants.tileWidth / 2)
        let y = (point.x + point.y) * (Constants.tileHeight / 2)
        return CGPoint(x: x, y: -y)
    }

    /// Convert screen-space isometric coordinates back to world position.
    static func screenToWorld(_ point: CGPoint) -> CGPoint {
        let adjustedY = -point.y
        let x = (point.x / (Constants.tileWidth / 2) + adjustedY / (Constants.tileHeight / 2)) / 2
        let y = (adjustedY / (Constants.tileHeight / 2) - point.x / (Constants.tileWidth / 2)) / 2
        return CGPoint(x: x, y: y)
    }

    /// Distance between two CGPoints.
    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return sqrt(dx * dx + dy * dy)
    }

    /// Normalized direction vector from `from` to `to`.
    static func direction(from: CGPoint, to: CGPoint) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0 else { return .zero }
        return CGPoint(x: dx / len, y: dy / len)
    }
}
