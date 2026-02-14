import SpriteKit

/// Base class for all modal overlay screens (pause, inventory, stats, codex, settings)
/// Provides semi-transparent background and fade in/out animations
class ModalOverlay: SKNode {
    // MARK: - Properties

    /// Semi-transparent dark overlay that blocks game interaction
    let backgroundOverlay: SKShapeNode

    /// Closure called when modal is dismissed
    var onDismiss: (() -> Void)?

    /// Whether tapping outside the content panel dismisses the modal
    var dismissOnBackgroundTap: Bool = false

    // MARK: - Initialization

    init(screenSize: CGSize) {
        // Create full-screen overlay
        backgroundOverlay = SKShapeNode(rectOf: screenSize)
        backgroundOverlay.fillColor = UITheme.darkStone.withAlphaComponent(UITheme.overlayAlpha)
        backgroundOverlay.strokeColor = .clear
        backgroundOverlay.zPosition = 0
        backgroundOverlay.isUserInteractionEnabled = true

        super.init()

        self.isUserInteractionEnabled = true
        addChild(backgroundOverlay)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Display Methods

    /// Show the modal with optional fade animation
    func show(animated: Bool) {
        if animated {
            alpha = 0
            run(SKAction.fadeIn(withDuration: UITheme.animationNormal))
        }
    }

    /// Dismiss the modal with optional fade animation
    func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        if animated {
            let fadeOut = SKAction.fadeOut(withDuration: UITheme.animationNormal)
            let remove = SKAction.removeFromParent()
            let sequence = SKAction.sequence([fadeOut, remove])

            run(sequence) { [weak self] in
                self?.onDismiss?()
                completion?()
            }
        } else {
            removeFrom

Parent()
            onDismiss?()
            completion?()
        }
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard dismissOnBackgroundTap, let touch = touches.first else {
            super.touchesBegan(touches, with: event)
            return
        }

        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        // Only dismiss if touch is directly on the background overlay
        if touchedNode == backgroundOverlay {
            dismiss(animated: true)
        } else {
            super.touchesBegan(touches, with: event)
        }
    }
}
