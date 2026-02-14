import SpriteKit

/// Enhanced stat bar component with medieval theming
/// Features ornamental frame, color-coded fill, icon, and value label
class StatBar: SKNode {
    // MARK: - Properties

    private let background: SKShapeNode
    private let fill: SKShapeNode
    private var iconNode: SKSpriteNode?
    private let valueLabel: SKLabelNode
    private let frameLeft: SKShapeNode
    private let frameRight: SKShapeNode

    private let barSize: CGSize
    private var maxValue: CGFloat
    private var currentValue: CGFloat = 0

    var fillColor: SKColor {
        didSet {
            fill.fillColor = fillColor
        }
    }

    // MARK: - Initialization

    init(size: CGSize = CGSize(width: 150, height: 16), maxValue: CGFloat, fillColor: SKColor = UITheme.forestGreen, icon: String? = nil) {
        self.barSize = size
        self.maxValue = maxValue
        self.fillColor = fillColor

        // Background (dark)
        background = SKShapeNode(rectOf: size, cornerRadius: 4)
        background.fillColor = UITheme.darkStone.withAlphaComponent(0.8)
        background.strokeColor = UITheme.gold.withAlphaComponent(0.5)
        background.lineWidth = 1
        background.zPosition = 0

        // Fill bar (colored)
        let fillSize = CGSize(width: size.width - 4, height: size.height - 4)
        fill = SKShapeNode(rectOf: fillSize, cornerRadius: 3)
        fill.fillColor = fillColor
        fill.strokeColor = .clear
        fill.zPosition = 1

        // Ornamental frame corners (rivets)
        let rivetRadius: CGFloat = 2
        frameLeft = SKShapeNode(circleOfRadius: rivetRadius)
        frameLeft.fillColor = UITheme.goldDark
        frameLeft.strokeColor = UITheme.gold
        frameLeft.lineWidth = 0.5
        frameLeft.position = CGPoint(x: -size.width / 2 + 4, y: 0)
        frameLeft.zPosition = 2

        frameRight = SKShapeNode(circleOfRadius: rivetRadius)
        frameRight.fillColor = UITheme.goldDark
        frameRight.strokeColor = UITheme.gold
        frameRight.lineWidth = 0.5
        frameRight.position = CGPoint(x: size.width / 2 - 4, y: 0)
        frameRight.zPosition = 2

        // Value label
        valueLabel = SKLabelNode(fontNamed: UITheme.monoFont)
        valueLabel.fontSize = UITheme.fontSizeSmall
        valueLabel.fontColor = UITheme.textLight
        valueLabel.verticalAlignmentMode = .center
        valueLabel.horizontalAlignmentMode = .center
        valueLabel.zPosition = 3

        super.init()

        addChild(background)
        addChild(fill)
        addChild(frameLeft)
        addChild(frameRight)
        addChild(valueLabel)

        // Add icon if provided
        if let iconName = icon {
            let icon = SKSpriteNode(imageNamed: iconName)
            icon.size = CGSize(width: 16, height: 16)
            icon.position = CGPoint(x: -size.width / 2 - 12, y: 0)
            icon.zPosition = 2
            addChild(icon)
            iconNode = icon
        }

        // Initial update
        update(value: maxValue, animated: false)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Update

    /// Update the bar's current value with optional animation
    func update(value: CGFloat, animated: Bool = true) {
        currentValue = max(0, min(value, maxValue))
        let ratio = currentValue / maxValue

        // Update fill scale
        if animated {
            let scaleAction = SKAction.scaleX(to: ratio, duration: UITheme.animationFast)
            scaleAction.timingMode = .easeOut
            fill.run(scaleAction)
        } else {
            fill.xScale = ratio
        }

        // Update label
        valueLabel.text = "\(Int(currentValue))/\(Int(maxValue))"

        // Color transition based on ratio
        updateColorForRatio(ratio)
    }

    /// Update max value (e.g., when player levels up and max health increases)
    func setMaxValue(_ newMax: CGFloat) {
        maxValue = newMax
        update(value: currentValue, animated: false)
    }

    // MARK: - Color Management

    private func updateColorForRatio(_ ratio: CGFloat) {
        // Default behavior: green -> yellow -> red as value decreases
        // Override this by setting fillColor directly if you want a fixed color
        if ratio > 0.5 {
            fill.fillColor = UITheme.forestGreen
        } else if ratio > 0.25 {
            fill.fillColor = SKColor.yellow
        } else {
            fill.fillColor = UITheme.crimson
        }
    }

    /// Set a fixed fill color (disables automatic color transitions)
    func setFixedColor(_ color: SKColor) {
        fillColor = color
        fill.fillColor = color
    }

    // MARK: - Convenience Methods

    /// Hide the value label
    func hideLabel() {
        valueLabel.isHidden = true
    }

    /// Show the value label
    func showLabel() {
        valueLabel.isHidden = false
    }
}
