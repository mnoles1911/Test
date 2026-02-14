import SpriteKit

/// Centralized theme system for medieval D&D-inspired UI styling
struct UITheme {
    // MARK: - Medieval Dark Mode Colors

    // Backgrounds
    static let parchmentLight = SKColor(red: 0.89, green: 0.82, blue: 0.69, alpha: 1.0)
    static let parchmentDark = SKColor(red: 0.65, green: 0.56, blue: 0.42, alpha: 1.0)
    static let darkStone = SKColor(red: 0.2, green: 0.2, blue: 0.22, alpha: 1.0)
    static let warmBrown = SKColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 1.0)
    static let leather = SKColor(red: 0.45, green: 0.35, blue: 0.25, alpha: 1.0)

    // Accents
    static let gold = SKColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 1.0)
    static let goldDark = SKColor(red: 0.65, green: 0.45, blue: 0.08, alpha: 1.0)
    static let crimson = SKColor(red: 0.545, green: 0.102, blue: 0.102, alpha: 1.0)
    static let forestGreen = SKColor(red: 0.176, green: 0.314, blue: 0.086, alpha: 1.0)
    static let royalBlue = SKColor(red: 0.118, green: 0.227, blue: 0.373, alpha: 1.0)

    // Text
    static let textLight = SKColor(red: 0.961, green: 0.902, blue: 0.827, alpha: 1.0)
    static let textDark = SKColor(red: 0.169, green: 0.141, blue: 0.098, alpha: 1.0)
    static let textGold = SKColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 1.0)
    static let textGray = SKColor(red: 0.541, green: 0.486, blue: 0.416, alpha: 1.0)

    // MARK: - Typography

    /// Titles and main menu headers (Copperplate-Bold, 28-36pt)
    static let titleFont = "Copperplate-Bold"

    /// Section headers and item names (Georgia-Bold, 18-24pt)
    static let headerFont = "Georgia-Bold"

    /// Body text and descriptions (Georgia, 14-16pt)
    static let bodyFont = "Georgia"

    /// Numbers and stats (Courier, 12-14pt)
    static let monoFont = "Courier"

    // Font Sizes
    static let fontSizeTitle: CGFloat = 32
    static let fontSizeHeader: CGFloat = 20
    static let fontSizeBody: CGFloat = 16
    static let fontSizeMono: CGFloat = 14
    static let fontSizeSmall: CGFloat = 12

    // MARK: - Sizing & Spacing

    static let cornerRadius: CGFloat = 8
    static let panelPadding: CGFloat = 20
    static let buttonHeight: CGFloat = 50
    static let buttonHeightSmall: CGFloat = 40

    // Spacing
    static let spacingTiny: CGFloat = 4
    static let spacingSmall: CGFloat = 8
    static let spacingMedium: CGFloat = 16
    static let spacingLarge: CGFloat = 24
    static let spacingXLarge: CGFloat = 32

    // MARK: - Animation Durations

    static let animationFast: TimeInterval = 0.15
    static let animationNormal: TimeInterval = 0.3
    static let animationSlow: TimeInterval = 0.5

    // MARK: - Shadows

    static let shadowOffset = CGSize(width: 0, height: 4)
    static let shadowRadius: CGFloat = 8
    static let shadowOpacity: Float = 0.5
    static let shadowColor = SKColor.black

    // MARK: - Overlay

    static let overlayAlpha: CGFloat = 0.7

    // MARK: - Helper Methods

    /// Creates a vertical gradient from top to bottom
    static func createVerticalGradient(from topColor: SKColor, to bottomColor: SKColor, size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [topColor.cgColor, bottomColor.cgColor] as CFArray
            let locations: [CGFloat] = [0.0, 1.0]

            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: size.width / 2, y: 0),
                    end: CGPoint(x: size.width / 2, y: size.height),
                    options: []
                )
            }
        }
        return SKTexture(image: image)
    }

    /// Creates a radial gradient from center to edges
    static func createRadialGradient(from centerColor: SKColor, to edgeColor: SKColor, size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [centerColor.cgColor, edgeColor.cgColor] as CFArray
            let locations: [CGFloat] = [0.0, 1.0]

            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = max(size.width, size.height) / 2
                cgContext.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: radius,
                    options: []
                )
            }
        }
        return SKTexture(image: image)
    }
}
