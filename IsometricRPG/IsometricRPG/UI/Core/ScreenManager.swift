import SpriteKit

/// Game state enum representing different screens/modes
enum GameState {
    case mainMenu
    case playing
    case paused
    case inventory
    case characterStats
    case codex
    case settings
    case gameOver
}

/// Manages screen state transitions and modal overlays
class ScreenManager {
    // MARK: - Properties

    private(set) var currentState: GameState = .playing
    weak var scene: SKScene?

    /// Stack of active modals (for nested modals)
    private var modalStack: [ModalOverlay] = []

    /// Callback when game state changes
    var onStateChanged: ((GameState) -> Void)?

    // MARK: - Initialization

    init(scene: SKScene, initialState: GameState = .playing) {
        self.scene = scene
        self.currentState = initialState
    }

    // MARK: - State Transitions

    /// Transition to a new game state
    func transition(to newState: GameState, animated: Bool = true) {
        let previousState = currentState
        currentState = newState

        print("[ScreenManager] Transitioning from \(previousState) to \(newState)")

        // Notify listeners
        onStateChanged?(newState)

        // Handle state-specific logic
        switch newState {
        case .playing:
            // Resume game loop
            dismissAllModals(animated: animated)

        case .paused:
            // Pause is handled via modals
            break

        case .mainMenu:
            // Return to main menu (will be presented via scene transition)
            dismissAllModals(animated: false)

        case .gameOver:
            // Game over is handled via modals
            break

        default:
            // Other states are modal overlays
            break
        }
    }

    // MARK: - Modal Management

    /// Show a modal overlay
    func showModal(_ modal: ModalOverlay, animated: Bool = true) {
        guard let scene = scene else { return }

        // Add modal to scene
        modal.zPosition = Constants.ZPosition.modal + CGFloat(modalStack.count)
        scene.addChild(modal)
        modalStack.append(modal)

        // Show with animation
        modal.show(animated: animated)

        // Setup dismiss callback
        modal.onDismiss = { [weak self] in
            self?.modalStack.removeAll { $0 == modal }
            if self?.modalStack.isEmpty == true {
                self?.transition(to: .playing, animated: false)
            }
        }
    }

    /// Dismiss the top modal
    func dismissModal(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let topModal = modalStack.last else {
            completion?()
            return
        }

        topModal.dismiss(animated: animated) {
            completion?()
        }
    }

    /// Dismiss all modals
    func dismissAllModals(animated: Bool = true) {
        let modals = modalStack
        modalStack.removeAll()

        for modal in modals {
            modal.dismiss(animated: animated)
        }
    }

    /// Check if any modal is currently showing
    var hasActiveModal: Bool {
        return !modalStack.isEmpty
    }

    /// Get the current top modal (if any)
    var topModal: ModalOverlay? {
        return modalStack.last
    }
}
