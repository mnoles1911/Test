import SpriteKit

/// Medieval-styled button with 3 states (normal, pressed, disabled)
/// Supports icon + text label with tap handling
class MedievalButton: SKNode {
    // MARK: - State

    enum State {
        case normal
        case pressed
        case disabled
    }

    private(set) var state: State = .normal {
        didSet {
            updateAppearance()
        }
    }

    // MARK: - Properties

    private let background: SKShapeNode
    private let label: SKLabelNode
    private var iconNode: SKSpriteNode?

    var text: String {
        get { label.text ?? "" }
        set { label.text = newValue }
    }

    var isEnabled: Bool = true {
        didSet {
            state = isEnabled ? .normal : .disabled
        }
    }

    /// Closure called when button is tapped (only when enabled)
    var onTap: (() -> Void)?

    private let size: CGSize

    // MARK: - Initialization

    init(text: String, icon: String? = nil, size: CGSize = CGSize(width: 240, height: UITheme.buttonHeight)) {
        self.size = size

        // Create background with rounded corners and gradient effect
        background = SKShapeNode(rectOf: size, cornerRadius: UITheme.cornerRadius)
        background.fillColor = UITheme.warmBrown
        background.strokeColor = UITheme.gold
        background.lineWidth = 2
        background.zPosition = 0

        // Create text label
        label = SKLabelNode(fontNamed: UITheme.headerFont)
        label.text = text
        label.fontSize = UITheme.fontSizeHeader
        label.fontColor = UITheme.textLight
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 2

        super.init()

        isUserInteractionEnabled = true

        addChild(background)
        addChild(label)

        // Add icon if provided
        if let iconName = icon {
            let icon = SKSpriteNode(imageNamed: iconName)
            icon.size = CGSize(width: 24, height: 24)
            icon.position = CGPoint(x: -size.width / 4, y: 0)
            icon.zPosition = 2
            addChild(icon)
            iconNode = icon

            // Shift label to the right to make room for icon
            label.position = CGPoint(x: size.width / 8, y: 0)
        }

        updateAppearance()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Appearance

    private func updateAppearance() {
        switch state {
        case .normal:
            background.fillColor = UITheme.warmBrown
            background.strokeColor = UITheme.gold
            label.fontColor = UITheme.textLight
            iconNode?.alpha = 1.0
            setScale(1.0)

        case .pressed:
            background.fillColor = UITheme.leather
            background.strokeColor = UITheme.goldDark
            label.fontColor = UITheme.textLight.withAlphaComponent(0.8)
            iconNode?.alpha = 0.8
            setScale(0.95)

        case .disabled:
            background.fillColor = UITheme.darkStone
            background.strokeColor = UITheme.textGray
            label.fontColor = UITheme.textGray
            iconNode?.alpha = 0.5
            setScale(1.0)
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isEnabled else { return }
        state = .pressed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isEnabled, state == .pressed else {
            state = .normal
            return
        }

        state = .normal

        // Check if touch ended inside button bounds
        if let touch = touches.first {
            let location = touch.location(in: parent ?? self)
            let localLocation = convert(location, from: parent ?? self)

            if background.contains(localLocation) {
                // Add scale animation
                let scaleUp = SKAction.scale(to: 1.1, duration: UITheme.animationFast)
                let scaleDown = SKAction.scale(to: 1.0, duration: UITheme.animationFast)
                run(SKAction.sequence([scaleUp, scaleDown])) { [weak self] in
                    self?.onTap?()
                }
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isEnabled else { return }
        state = .normal
    }

    // MARK: - Convenience Methods

    /// Creates a small-sized button
    static func small(text: String, icon: String? = nil) -> MedievalButton {
        return MedievalButton(
            text: text,
            icon: icon,
            size: CGSize(width: 180, height: UITheme.buttonHeightSmall)
        )
    }

    /// Creates a large-sized button
    static func large(text: String, icon: String? = nil) -> MedievalButton {
        return MedievalButton(
            text: text,
            icon: icon,
            size: CGSize(width: 300, height: UITheme.buttonHeight + 10)
        )
    }
}
