import UIKit
import SpriteKit

final class GameViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        guard let skView = view as? SKView else {
            let skView = SKView(frame: view.bounds)
            skView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(skView)
            configureView(skView)
            return
        }
        configureView(skView)
    }

    private func configureView(_ skView: SKView) {
        skView.ignoresSiblingOrder = false
        skView.showsFPS = true
        skView.showsNodeCount = true
        skView.isMultipleTouchEnabled = true

        // Launch Main Menu instead of going directly to game
        let scene = MainMenuScreen(size: skView.bounds.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override var shouldAutorotate: Bool {
        return true
    }

    override func loadView() {
        self.view = SKView()
    }
}
