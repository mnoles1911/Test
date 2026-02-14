import SpriteKit

/// Parchment-styled panel with ornamental border and optional title
class MedievalPanel: SKNode {
    // MARK: - Properties

    private let background: SKShapeNode
    private let border: SKShapeNode
    private var titleBanner: SKNode?
    private let contentNode: SKNode

    private let size: CGSize

    var title: String? {
        didSet {
            updateTitle()
        }
    }

    // MARK: - Initialization

    init(size: CGSize, title: String? = nil) {
        self.size = size

        // Create parchment background with radial gradient effect
        background = SKShapeNode(rectOf: size, cornerRadius: UITheme.cornerRadius)
        background.fillColor = UITheme.parchmentLight
        background.strokeColor = .clear
        background.zPosition = 0

        // Create ornamental border
        border = SKShapeNode(rectOf: size, cornerRadius: UITheme.cornerRadius)
        border.fillColor = .clear
        border.strokeColor = UITheme.gold
        border.lineWidth = 3
        border.zPosition = 1

        // Content container (child nodes go here)
        contentNode = SKNode()
        contentNode.zPosition = 2

        super.init()

        addChild(background)
        addChild(border)
        addChild(contentNode)

        // Add corner decorations (rivets)
        addCornerDecorations()

        // Add title if provided
        if let titleText = title {
            self.title = titleText
            updateTitle()
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Content Management

    /// Add content to the panel (will be positioned relative to panel center)
    func addContent(_ node: SKNode) {
        contentNode.addChild(node)
    }

    /// Remove all content from the panel
    func clearContent() {
        contentNode.removeAllChildren()
    }

    // MARK: - Title

    private func updateTitle() {
        // Remove existing title banner
        titleBanner?.removeFromParent()
        titleBanner = nil

        guard let titleText = title else { return }

        // Create title banner
        let bannerHeight: CGFloat = 50
        let bannerWidth = size.width * 0.6

        let banner = SKNode()
        banner.zPosition = 3

        // Banner background
        let bannerBg = SKShapeNode(rectOf: CGSize(width: bannerWidth, height: bannerHeight), cornerRadius: 6)
        bannerBg.fillColor = UITheme.warmBrown
        bannerBg.strokeColor = UITheme.gold
        bannerBg.lineWidth = 2
        banner.addChild(bannerBg)

        // Title text
        let titleLabel = SKLabelNode(fontNamed: UITheme.titleFont)
        titleLabel.text = titleText
        titleLabel.fontSize = UITheme.fontSizeHeader
        titleLabel.fontColor = UITheme.textGold
        titleLabel.verticalAlignmentMode = .center
        titleLabel.horizontalAlignmentMode = .center
        banner.addChild(titleLabel)

        // Position at top center of panel
        banner.position = CGPoint(x: 0, y: size.height / 2 - bannerHeight / 2 + 10)

        addChild(banner)
        titleBanner = banner
    }

    // MARK: - Decorations

    private func addCornerDecorations() {
        let rivetRadius: CGFloat = 4
        let rivetColor = UITheme.goldDark
        let inset: CGFloat = 10

        // Create corner positions
        let corners: [CGPoint] = [
            CGPoint(x: -size.width / 2 + inset, y: size.height / 2 - inset),   // Top-left
            CGPoint(x: size.width / 2 - inset, y: size.height / 2 - inset),    // Top-right
            CGPoint(x: -size.width / 2 + inset, y: -size.height / 2 + inset),  // Bottom-left
            CGPoint(x: size.width / 2 - inset, y: -size.height / 2 + inset)    // Bottom-right
        ]

        // Add decorative rivets at corners
        for cornerPos in corners {
            let rivet = SKShapeNode(circleOfRadius: rivetRadius)
            rivet.fillColor = rivetColor
            rivet.strokeColor = UITheme.gold
            rivet.lineWidth = 1
            rivet.position = cornerPos
            rivet.zPosition = 2
            addChild(rivet)
        }
    }

    // MARK: - Convenience Initializers

    /// Creates a small panel (400x300)
    static func small(title: String? = nil) -> MedievalPanel {
        return MedievalPanel(size: CGSize(width: 400, height: 300), title: title)
    }

    /// Creates a medium panel (600x400)
    static func medium(title: String? = nil) -> MedievalPanel {
        return MedievalPanel(size: CGSize(width: 600, height: 400), title: title)
    }

    /// Creates a large panel (800x600)
    static func large(title: String? = nil) -> MedievalPanel {
        return MedievalPanel(size: CGSize(width: 800, height: 600), title: title)
    }
}
