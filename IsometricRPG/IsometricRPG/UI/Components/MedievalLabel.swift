import SpriteKit

/// Styled label with drop shadow and medieval theming
class MedievalLabel: SKNode {
    // MARK: - Style

    enum Style {
        case title      // Large gold text (Copperplate-Bold)
        case header     // Medium text (Georgia-Bold)
        case body       // Normal text (Georgia)
        case mono       // Monospaced numbers (Courier)
        case small      // Small text
    }

    // MARK: - Properties

    private let label: SKLabelNode
    private var shadowLabel: SKLabelNode?

    var text: String {
        get { label.text ?? "" }
        set {
            label.text = newValue
            shadowLabel?.text = newValue
        }
    }

    var fontColor: SKColor {
        get { label.fontColor ?? UITheme.textLight }
        set { label.fontColor = newValue }
    }

    // MARK: - Initialization

    init(text: String, style: Style, withShadow: Bool = true, color: SKColor? = nil) {
        label = SKLabelNode()
        label.text = text
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 1

        // Apply style
        switch style {
        case .title:
            label.fontName = UITheme.titleFont
            label.fontSize = UITheme.fontSizeTitle
            label.fontColor = color ?? UITheme.textGold

        case .header:
            label.fontName = UITheme.headerFont
            label.fontSize = UITheme.fontSizeHeader
            label.fontColor = color ?? UITheme.textLight

        case .body:
            label.fontName = UITheme.bodyFont
            label.fontSize = UITheme.fontSizeBody
            label.fontColor = color ?? UITheme.textLight

        case .mono:
            label.fontName = UITheme.monoFont
            label.fontSize = UITheme.fontSizeMono
            label.fontColor = color ?? UITheme.textLight

        case .small:
            label.fontName = UITheme.bodyFont
            label.fontSize = UITheme.fontSizeSmall
            label.fontColor = color ?? UITheme.textGray
        }

        super.init()

        // Add shadow if requested
        if withShadow {
            let shadow = SKLabelNode()
            shadow.text = text
            shadow.fontName = label.fontName
            shadow.fontSize = label.fontSize
            shadow.fontColor = UITheme.shadowColor.withAlphaComponent(0.5)
            shadow.verticalAlignmentMode = .center
            shadow.horizontalAlignmentMode = .center
            shadow.position = CGPoint(x: 2, y: -2)
            shadow.zPosition = 0
            addChild(shadow)
            shadowLabel = shadow
        }

        addChild(label)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Alignment

    func setHorizontalAlignment(_ mode: SKLabelHorizontalAlignmentMode) {
        label.horizontalAlignmentMode = mode
        shadowLabel?.horizontalAlignmentMode = mode
    }

    func setVerticalAlignment(_ mode: SKLabelVerticalAlignmentMode) {
        label.verticalAlignmentMode = mode
        shadowLabel?.verticalAlignmentMode = mode
    }

    // MARK: - Animation

    /// Fade in the label
    func fadeIn(duration: TimeInterval = UITheme.animationNormal) {
        alpha = 0
        run(SKAction.fadeIn(withDuration: duration))
    }

    /// Pulse animation (scale up and down)
    func pulse(scale: CGFloat = 1.2, duration: TimeInterval = 0.5) {
        let scaleUp = SKAction.scale(to: scale, duration: duration / 2)
        let scaleDown = SKAction.scale(to: 1.0, duration: duration / 2)
        let sequence = SKAction.sequence([scaleUp, scaleDown])
        run(SKAction.repeatForever(sequence))
    }

    /// Stop all animations
    func stopAnimations() {
        removeAllActions()
    }
}
