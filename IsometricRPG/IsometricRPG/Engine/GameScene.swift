import SpriteKit

final class GameScene: SKScene {
    // MARK: - Game Objects
    private var tileMap: TileMap!
    private var player: Player!
    private var enemies: [Enemy] = []
    private var combatSystem: CombatSystem!
    private var enhancedHUD: EnhancedHUD!
    private var screenManager: ScreenManager!
    private var gameState: GameState = .playing

    // MARK: - Input
    private var moveJoystick: VirtualJoystick!
    private var aimJoystick: VirtualJoystick!

    // MARK: - Game State
    private var lastUpdateTime: TimeInterval = 0
    private var lastSpawnTime: TimeInterval = 0
    private var killCount: Int = 0
    private var isGameOver: Bool = false

    // MARK: - Camera
    private var cameraNode: SKCameraNode!
    private let worldNode = SKNode()

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = UITheme.darkStone
        setupCamera()
        setupWorld()
        setupPlayer()
        setupCombat()
        setupScreenManager()
        setupHUD()
        setupInput()
    }

    // MARK: - Setup

    private func setupCamera() {
        cameraNode = SKCameraNode()
        camera = cameraNode
        addChild(cameraNode)
    }

    private func setupWorld() {
        addChild(worldNode)
        tileMap = TileMap()
        worldNode.addChild(tileMap.rootNode)
    }

    private func setupPlayer() {
        let spawnCol = Constants.mapColumns / 2
        let spawnRow = Constants.mapRows / 2
        player = Player(worldPosition: CGPoint(x: CGFloat(spawnCol), y: CGFloat(spawnRow)))
        worldNode.addChild(player.node)
    }

    private func setupCombat() {
        combatSystem = CombatSystem(worldNode: worldNode)
    }

    private func setupScreenManager() {
        screenManager = ScreenManager(scene: self, initialState: .playing)
        screenManager.onStateChanged = { [weak self] newState in
            self?.gameState = newState
        }
    }

    private func setupHUD() {
        enhancedHUD = EnhancedHUD()
        enhancedHUD.setTileMap(tileMap)
        enhancedHUD.onPauseTapped = { [weak self] in
            self?.showPauseMenu()
        }
        cameraNode.addChild(enhancedHUD)
        layoutHUD()
    }

    private func setupInput() {
        moveJoystick = VirtualJoystick(color: SKColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1))
        aimJoystick = VirtualJoystick(color: SKColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1))
        cameraNode.addChild(moveJoystick)
        cameraNode.addChild(aimJoystick)
        layoutJoysticks()
    }

    private func layoutJoysticks() {
        guard let view = view else { return }
        let safeLeft = -view.bounds.width / 2
        let safeBottom = -view.bounds.height / 2
        let margin: CGFloat = 80

        moveJoystick.position = CGPoint(x: safeLeft + margin + 20, y: safeBottom + margin + 20)
        aimJoystick.position = CGPoint(x: -safeLeft - margin - 20, y: safeBottom + margin + 20)
    }

    private func layoutHUD() {
        guard let view = view else { return }
        enhancedHUD.layout(screenSize: view.bounds.size)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutJoysticks()
        layoutHUD()
    }

    // MARK: - Game Loop

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver && gameState == .playing else { return }

        let dt: TimeInterval
        if lastUpdateTime == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = min(currentTime - lastUpdateTime, 1.0 / 30.0) // cap dt
        }
        lastUpdateTime = currentTime

        updatePlayer(deltaTime: dt, currentTime: currentTime)
        updateEnemies(deltaTime: dt, currentTime: currentTime)
        spawnEnemies(currentTime: currentTime)
        combatSystem.update(deltaTime: dt, currentTime: currentTime, enemies: &enemies, player: player)
        collectXPOrbs()
        updateCamera()
        enhancedHUD.update(player: player, enemies: enemies, killCount: killCount, currentTime: currentTime)

        if !player.isAlive {
            gameOver()
        }
    }

    // MARK: - Player Update

    private func updatePlayer(deltaTime: TimeInterval, currentTime: TimeInterval) {
        // Read joystick input
        player.moveDirection = moveJoystick.direction
        player.aimDirection = aimJoystick.direction
        player.isShooting = aimJoystick.isActive

        // Store old position for collision revert
        let oldPos = player.worldPosition
        player.update(deltaTime: deltaTime)

        // Collision check against non-walkable tiles
        if !tileMap.isWalkable(worldPosition: player.worldPosition) {
            player.worldPosition = oldPos
            player.syncNodePosition()
        }

        // Clamp to map bounds
        player.worldPosition.x = max(1, min(CGFloat(Constants.mapColumns - 2), player.worldPosition.x))
        player.worldPosition.y = max(1, min(CGFloat(Constants.mapRows - 2), player.worldPosition.y))
        player.syncNodePosition()

        // Fire
        if player.canFire(currentTime: currentTime) {
            // Convert iso aim direction to world direction
            let aimDir = player.aimDirection
            // Normalize for isometric: screen-space aim -> world-space direction
            let worldDir = CGPoint(
                x: aimDir.x / (Constants.tileWidth / 2) + aimDir.y / (Constants.tileHeight / 2),
                y: -aimDir.x / (Constants.tileWidth / 2) + aimDir.y / (Constants.tileHeight / 2)
            )
            let len = sqrt(worldDir.x * worldDir.x + worldDir.y * worldDir.y)
            guard len > 0 else { return }
            let normalizedDir = CGPoint(x: worldDir.x / len, y: worldDir.y / len)

            combatSystem.fireBullet(from: player.worldPosition, direction: normalizedDir, at: currentTime)
            player.didFire(at: currentTime)
        }
    }

    // MARK: - Enemies

    private func updateEnemies(deltaTime: TimeInterval, currentTime: TimeInterval) {
        let beforeCount = enemies.count

        for enemy in enemies where enemy.isAlive {
            enemy.updateAI(playerPosition: player.worldPosition, currentTime: currentTime)
            enemy.update(deltaTime: deltaTime)

            // Enemy attacks player
            if enemy.canAttack(currentTime: currentTime) {
                player.takeDamage(Constants.enemyAttackDamage)
                enemy.lastAttackTime = currentTime
            }
        }

        let afterCount = enemies.filter { $0.isAlive }.count
        killCount += (beforeCount - afterCount)
    }

    private func spawnEnemies(currentTime: TimeInterval) {
        let aliveCount = enemies.filter { $0.isAlive }.count
        guard aliveCount < Constants.maxEnemies,
              currentTime - lastSpawnTime > Constants.enemySpawnInterval else { return }

        lastSpawnTime = currentTime

        // Pick a random walkable tile that's far enough from the player
        var attempts = 0
        while attempts < 20 {
            let col = Int.random(in: 2..<(Constants.mapColumns - 2))
            let row = Int.random(in: 2..<(Constants.mapRows - 2))
            let pos = CGPoint(x: CGFloat(col), y: CGFloat(row))

            if tileMap.isWalkable(col: col, row: row) &&
               IsometricMath.distance(pos, player.worldPosition) > 4 {
                let enemy = Enemy(worldPosition: pos)
                enemies.append(enemy)
                worldNode.addChild(enemy.node)

                // Spawn animation
                enemy.node.setScale(0)
                enemy.node.run(SKAction.scale(to: 1.0, duration: 0.3))
                break
            }
            attempts += 1
        }
    }

    // MARK: - XP Collection

    private func collectXPOrbs() {
        let playerScreenPos = player.node.position
        worldNode.enumerateChildNodes(withName: "xpOrb_*") { [weak self] node, _ in
            guard let self = self else { return }
            let dist = IsometricMath.distance(node.position, playerScreenPos)
            if dist < 25 {
                // Parse XP value from name
                if let name = node.name, let xpStr = name.split(separator: "_").last,
                   let xp = Int(xpStr) {
                    self.player.gainExperience(xp)
                }
                node.run(SKAction.sequence([
                    SKAction.group([
                        SKAction.scale(to: 0, duration: 0.15),
                        SKAction.fadeOut(withDuration: 0.15)
                    ]),
                    SKAction.removeFromParent()
                ]))
            } else if dist < 80 {
                // Attract orbs toward player
                let dir = IsometricMath.direction(from: node.position, to: playerScreenPos)
                node.position = CGPoint(
                    x: node.position.x + dir.x * 2,
                    y: node.position.y + dir.y * 2
                )
            }
        }
    }

    // MARK: - Camera

    private func updateCamera() {
        let target = player.node.position
        let smooth: CGFloat = 0.1
        let current = cameraNode.position
        cameraNode.position = CGPoint(
            x: current.x + (target.x - current.x) * smooth,
            y: current.y + (target.y - current.y) * smooth
        )
    }

    // MARK: - Game Over

    private func gameOver() {
        isGameOver = true
        combatSystem.removeAll()

        let overlay = SKShapeNode(rectOf: size)
        overlay.fillColor = SKColor.black.withAlphaComponent(0.7)
        overlay.strokeColor = .clear
        overlay.zPosition = Constants.ZPosition.hud + 10
        cameraNode.addChild(overlay)

        let gameOverLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        gameOverLabel.text = "GAME OVER"
        gameOverLabel.fontSize = 36
        gameOverLabel.fontColor = .red
        gameOverLabel.position = CGPoint(x: 0, y: 30)
        gameOverLabel.zPosition = Constants.ZPosition.hud + 11
        cameraNode.addChild(gameOverLabel)

        let statsLabel = SKLabelNode(fontNamed: "Helvetica")
        statsLabel.text = "Level \(player.level) | Kills: \(killCount)"
        statsLabel.fontSize = 18
        statsLabel.fontColor = .white
        statsLabel.position = CGPoint(x: 0, y: -10)
        statsLabel.zPosition = Constants.ZPosition.hud + 11
        cameraNode.addChild(statsLabel)

        let restartLabel = SKLabelNode(fontNamed: "Helvetica")
        restartLabel.text = "Tap to Restart"
        restartLabel.fontSize = 16
        restartLabel.fontColor = SKColor.white.withAlphaComponent(0.7)
        restartLabel.position = CGPoint(x: 0, y: -40)
        restartLabel.zPosition = Constants.ZPosition.hud + 11
        restartLabel.name = "restartPrompt"
        cameraNode.addChild(restartLabel)

        let blink = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 0.5),
            SKAction.fadeAlpha(to: 1.0, duration: 0.5)
        ])
        restartLabel.run(SKAction.repeatForever(blink))
    }

    // MARK: - Touch (Game Over restart)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isGameOver {
            restartGame()
        }
        super.touchesBegan(touches, with: event)
    }

    private func restartGame() {
        guard let view = self.view else { return }
        let newScene = GameScene(size: view.bounds.size)
        newScene.scaleMode = .resizeFill
        view.presentScene(newScene, transition: SKTransition.fade(withDuration: 0.5))
    }

    // MARK: - Pause Menu

    private func showPauseMenu() {
        guard let view = view else { return }

        let pauseMenu = PauseMenuScreen(screenSize: view.bounds.size)

        pauseMenu.onResume = { [weak self] in
            self?.screenManager.transition(to: .playing)
        }

        pauseMenu.onInventory = { [weak self] in
            self?.showInventory()
        }

        pauseMenu.onCharacter = { [weak self] in
            // TODO: Phase 4 - Character stats screen
            print("[GameScene] Character screen not yet implemented")
        }

        pauseMenu.onSettings = { [weak self] in
            // TODO: Phase 4 - Settings screen
            print("[GameScene] Settings screen not yet implemented")
        }

        pauseMenu.onMainMenu = { [weak self] in
            self?.returnToMainMenu()
        }

        screenManager.transition(to: .paused)
        screenManager.showModal(pauseMenu, animated: true)
    }

    private func showInventory() {
        guard let view = view else { return }

        let inventoryScreen = InventoryScreen(
            screenSize: view.bounds.size,
            inventory: player.inventory,
            equipment: player.equipment
        )

        inventoryScreen.onClose = { [weak self] in
            self?.screenManager.dismissModal(animated: true)
        }

        screenManager.showModal(inventoryScreen, animated: true)
    }

    private func returnToMainMenu() {
        guard let view = view else { return }

        // Transition back to main menu
        let mainMenu = MainMenuScreen(size: view.bounds.size)
        mainMenu.scaleMode = .resizeFill
        view.presentScene(mainMenu, transition: SKTransition.fade(withDuration: UITheme.animationSlow))
    }
}
