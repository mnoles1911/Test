import SpriteKit

/// Reusable animation library for UI elements
enum UIAnimations {
    // MARK: - Fade Animations

    static func fadeIn(duration: TimeInterval = UITheme.animationNormal) -> SKAction {
        return SKAction.fadeIn(withDuration: duration)
    }

    static func fadeOut(duration: TimeInterval = UITheme.animationNormal) -> SKAction {
        return SKAction.fadeOut(withDuration: duration)
    }

    // MARK: - Scale Animations

    static func scaleUp(to scale: CGFloat = 1.1, duration: TimeInterval = UITheme.animationFast) -> SKAction {
        return SKAction.scale(to: scale, duration: duration)
    }

    static func scaleDown(to scale: CGFloat = 1.0, duration: TimeInterval = UITheme.animationFast) -> SKAction {
        return SKAction.scale(to: scale, duration: duration)
    }

    static func pulse(minScale: CGFloat = 0.95, maxScale: CGFloat = 1.05, duration: TimeInterval = 1.0) -> SKAction {
        let scaleUp = SKAction.scale(to: maxScale, duration: duration / 2)
        scaleUp.timingMode = .easeInEaseOut
        let scaleDown = SKAction.scale(to: minScale, duration: duration / 2)
        scaleDown.timingMode = .easeInEaseOut
        return SKAction.repeatForever(SKAction.sequence([scaleUp, scaleDown]))
    }

    static func bounce(scale: CGFloat = 1.2, duration: TimeInterval = 0.3) -> SKAction {
        let scaleUp = SKAction.scale(to: scale, duration: duration / 2)
        scaleUp.timingMode = .easeOut
        let scaleDown = SKAction.scale(to: 1.0, duration: duration / 2)
        scaleDown.timingMode = .easeIn
        return SKAction.sequence([scaleUp, scaleDown])
    }

    // MARK: - Movement Animations

    static func slideIn(from direction: Direction, distance: CGFloat = 100, duration: TimeInterval = UITheme.animationNormal) -> SKAction {
        let offset = direction.offset(distance: distance)
        let move = SKAction.moveBy(x: -offset.x, y: -offset.y, duration: duration)
        move.timingMode = .easeOut
        return move
    }

    static func slideOut(to direction: Direction, distance: CGFloat = 100, duration: TimeInterval = UITheme.animationNormal) -> SKAction {
        let offset = direction.offset(distance: distance)
        let move = SKAction.moveBy(x: offset.x, y: offset.y, duration: duration)
        move.timingMode = .easeIn
        return move
    }

    static func shake(duration: TimeInterval = 0.3, amplitude: CGFloat = 5) -> SKAction {
        let moveLeft = SKAction.moveBy(x: -amplitude, y: 0, duration: duration / 8)
        let moveRight = SKAction.moveBy(x: amplitude * 2, y: 0, duration: duration / 4)
        let moveBack = SKAction.moveBy(x: -amplitude, y: 0, duration: duration / 8)
        return SKAction.sequence([moveLeft, moveRight, moveLeft, moveRight, moveBack])
    }

    // MARK: - Rotation Animations

    static func rotate(by angle: CGFloat, duration: TimeInterval = UITheme.animationNormal) -> SKAction {
        return SKAction.rotate(byAngle: angle, duration: duration)
    }

    static func spin(duration: TimeInterval = 1.0) -> SKAction {
        return SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: duration))
    }

    // MARK: - Blink Animation

    static func blink(interval: TimeInterval = 0.5) -> SKAction {
        let fadeOut = SKAction.fadeAlpha(to: 0.3, duration: interval)
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: interval)
        return SKAction.repeatForever(SKAction.sequence([fadeOut, fadeIn]))
    }

    // MARK: - Combined Animations

    static func popIn(duration: TimeInterval = UITheme.animationNormal) -> SKAction {
        let scaleUp = SKAction.scale(to: 1.2, duration: duration / 2)
        scaleUp.timingMode = .easeOut
        let scaleDown = SKAction.scale(to: 1.0, duration: duration / 2)
        scaleDown.timingMode = .easeIn
        let fadeIn = SKAction.fadeIn(withDuration: duration)

        return SKAction.group([
            SKAction.sequence([scaleUp, scaleDown]),
            fadeIn
        ])
    }

    static func popOut(duration: TimeInterval = UITheme.animationNormal) -> SKAction {
        let scaleDown = SKAction.scale(to: 0.8, duration: duration / 2)
        scaleDown.timingMode = .easeIn
        let scaleSmaller = SKAction.scale(to: 0, duration: duration / 2)
        scaleSmaller.timingMode = .easeOut
        let fadeOut = SKAction.fadeOut(withDuration: duration)

        return SKAction.group([
            SKAction.sequence([scaleDown, scaleSmaller]),
            fadeOut
        ])
    }

    // MARK: - Utility

    static func wait(_ duration: TimeInterval) -> SKAction {
        return SKAction.wait(forDuration: duration)
    }

    static func sequence(_ actions: [SKAction]) -> SKAction {
        return SKAction.sequence(actions)
    }

    static func group(_ actions: [SKAction]) -> SKAction {
        return SKAction.group(actions)
    }

    // MARK: - Direction Helper

    enum Direction {
        case up, down, left, right

        func offset(distance: CGFloat) -> CGPoint {
            switch self {
            case .up:    return CGPoint(x: 0, y: distance)
            case .down:  return CGPoint(x: 0, y: -distance)
            case .left:  return CGPoint(x: -distance, y: 0)
            case .right: return CGPoint(x: distance, y: 0)
            }
        }
    }
}
