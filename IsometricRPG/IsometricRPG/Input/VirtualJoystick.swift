import SpriteKit

/// A virtual joystick for touch input. Place two of these in the HUD:
/// one for movement (left) and one for aiming (right).
final class VirtualJoystick: SKNode {
    private let base: SKShapeNode
    private let knob: SKShapeNode
    private let radius: CGFloat
    private var trackingTouch: UITouch?

    /// Normalized direction output (-1...1 on each axis).
    private(set) var direction: CGPoint = .zero
    /// Whether the joystick is currently being held.
    private(set) var isActive: Bool = false

    init(radius: CGFloat = Constants.joystickRadius, color: SKColor = .gray) {
        self.radius = radius

        base = SKShapeNode(circleOfRadius: radius)
        base.fillColor = color.withAlphaComponent(0.2)
        base.strokeColor = color.withAlphaComponent(0.4)
        base.lineWidth = 2

        knob = SKShapeNode(circleOfRadius: Constants.joystickKnobRadius)
        knob.fillColor = color.withAlphaComponent(0.5)
        knob.strokeColor = color.withAlphaComponent(0.7)
        knob.lineWidth = 1.5

        super.init()
        isUserInteractionEnabled = true

        addChild(base)
        addChild(knob)
        zPosition = Constants.ZPosition.hud
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackingTouch == nil, let touch = touches.first else { return }
        trackingTouch = touch
        isActive = true
        updateKnob(for: touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackingTouch, touches.contains(touch) else { return }
        updateKnob(for: touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackingTouch, touches.contains(touch) else { return }
        resetJoystick()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackingTouch, touches.contains(touch) else { return }
        resetJoystick()
    }

    private func updateKnob(for touch: UITouch) {
        let loc = touch.location(in: self)
        let dx = loc.x
        let dy = loc.y
        let dist = sqrt(dx * dx + dy * dy)

        if dist <= radius {
            knob.position = loc
        } else {
            knob.position = CGPoint(x: dx / dist * radius, y: dy / dist * radius)
        }

        let normalizedDist = min(dist / radius, 1.0)
        if normalizedDist < Constants.joystickDeadZone {
            direction = .zero
        } else if dist > 0 {
            direction = CGPoint(x: dx / dist * normalizedDist, y: dy / dist * normalizedDist)
        }
    }

    private func resetJoystick() {
        trackingTouch = nil
        isActive = false
        direction = .zero
        let snap = SKAction.move(to: .zero, duration: 0.1)
        snap.timingMode = .easeOut
        knob.run(snap)
    }
}
