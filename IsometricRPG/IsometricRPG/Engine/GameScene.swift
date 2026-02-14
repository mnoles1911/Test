import SpriteKit

final class GameScene: SKScene {
    // MARK: - Game Objects
    private var worldManager: WorldManager!
    private var player: Player!
    private var enemies: [Enemy] = []
    private var combatSystem: CombatSystem!
    private var enhancedHUD: EnhancedHUD!
    private var screenManager: ScreenManager!
    private var gameState: GameState = .playing
    private var itemSpawner: ItemSpawner!

    // MARK: - Input
    private var moveJoystick: VirtualJoystick!
    private var aimJoystick: VirtualJoystick!

    // MARK: - Game State
    private var lastUpdateTime: TimeInterval = 0
    private var gameStartTime: TimeInterval = 0
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
        setupItems()
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
        worldManager = WorldManager()
        worldNode.addChild(worldManager.rootNode)
    }

    private func setupPlayer() {
        player = Player(worldPosition: CGPoint(x: 8, y: 8))
        worldNode.addChild(player.node)
        worldManager.initialLoad(around: player.worldPosition)
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

    private func setupItems() {
        itemSpawner = ItemSpawner(worldNode: worldNode)
        let context = buildGameContext()
        for chunk in worldManager.chunksNeedingItemSpawn() {
            itemSpawner.spawnItems(in: chunk, context: context)
        }
    }

    private func setupHUD() {
        enhancedHUD = EnhancedHUD()
        enhancedHUD.setWorldManager(worldManager)
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

        if gameStartTime == 0 { gameStartTime = currentTime }

        let dt: TimeInterval
        if lastUpdateTime == 0 {
            dt = 1.0 / 60.0
        } else {
            dt = min(currentTime - lastUpdateTime, 1.0 / 30.0)
        }
        lastUpdateTime = currentTime

        updatePlayer(deltaTime: dt, currentTime: currentTime)
        updateWorld()
        updateEnemies(deltaTime: dt, currentTime: currentTime)
        spawnEnemiesInChunks(currentTime: currentTime)
        combatSystem.update(deltaTime: dt, currentTime: currentTime, enemies: &enemies, player: player)
        itemSpawner.collectItems(near: player)
        collectXPOrbs()
        player.updateBuffs(deltaTime: dt)
        updateCamera()
        enhancedHUD.update(player: player, enemies: enemies, killCount: killCount, currentTime: currentTime)

        if !player.isAlive {
            gameOver()
        }
    }

    // MARK: - World Streaming

    private func updateWorld() {
        let result = worldManager.updateAroundPlayer(worldPosition: player.worldPosition)

        if !result.loaded.isEmpty {
            let context = buildGameContext()
            for coord in result.loaded {
                if let chunk = worldManager.loadedChunks[coord] {
                    itemSpawner.spawnItems(in: chunk, context: context)
                }
            }
        }

        for coord in result.unloaded {
            itemSpawner.removeItems(inChunk: coord)
            removeEnemies(inChunk: coord)
        }
    }

    // MARK: - Game Context for Triggers

    private func buildGameContext() -> GameContext {
        let elapsed = lastUpdateTime > 0 ? lastUpdateTime - gameStartTime : 0
        return GameContext(
            playerLevel: player?.level ?? 1,
            playerHealth: player?.health ?? Constants.playerMaxHealth,
            playerMaxHealth: player?.maxHealth ?? Constants.playerMaxHealth,
            playerArmor: player?.armor ?? 0,
            killCount: killCount,
            timeElapsed: elapsed,
            currentBiome: worldManager.biomeAt(worldPosition: player?.worldPosition ?? .zero),
            playerWorldPosition: player?.worldPosition ?? .zero,
            activeBuffCount: player?.activeBuffCount ?? 0
        )
    }

    // MARK: - Player Update

    private func updatePlayer(deltaTime: TimeInterval, currentTime: TimeInterval) {
        player.moveDirection = moveJoystick.direction
        player.aimDirection = aimJoystick.direction
        player.isShooting = aimJoystick.isActive

        let oldPos = player.worldPosition
        player.update(deltaTime: deltaTime)

        // Collision with wall-slide
        if !worldManager.isWalkable(worldPosition: player.worldPosition) {
            let slideX = CGPoint(x: player.worldPosition.x, y: oldPos.y)
            let slideY = CGPoint(x: oldPos.x, y: player.worldPosition.y)

            if worldManager.isWalkable(worldPosition: slideX) {
                player.worldPosition = slideX
            } else if worldManager.isWalkable(worldPosition: slideY) {
                player.worldPosition = slideY
            } else {
                player.worldPosition = oldPos
            }
            player.syncNodePosition()
        }

        // Fire
        if player.canFire(currentTime: currentTime) {
            let aimDir = player.aimDirection
            let worldDir = CGPoint(
                x: aimDir.x / (Constants.tileWidth / 2) + aimDir.y / (Constants.tileHeight / 2),
                y: -aimDir.x / (Constants.tileWidth / 2) + aimDir.y / (Constants.tileHeight / 2)
            )
            let len = sqrt(worldDir.x * worldDir.x + worldDir.y * worldDir.y)
            guard len > 0 else { return }
            let normalizedDir = CGPoint(x: worldDir.x / len, y: worldDir.y / len)

            // Phase 5: Play shoot sound
            AudioManager.shared.playSound(AudioManager.SoundEffect.shoot, volume: 0.5)

            combatSystem.fireBullet(from: player.worldPosition, direction: normalizedDir, at: currentTime)
            player.didFire(at: currentTime)
        }
    }

    // MARK: - Enemies (Chunk-based)

    private func updateEnemies(deltaTime: TimeInterval, currentTime: TimeInterval) {
        let beforeAlive = enemies.filter { $0.isAlive }.count

        for enemy in enemies where enemy.isAlive {
            enemy.updateAI(playerPosition: player.worldPosition, currentTime: currentTime)
            enemy.update(deltaTime: deltaTime)

            if enemy.canAttack(currentTime: currentTime) {
                // Phase 5: Play hit player sound
                AudioManager.shared.playSound(AudioManager.SoundEffect.hitPlayer)

                player.takeDamage(Constants.enemyAttackDamage)
                enemy.lastAttackTime = currentTime
            }
        }

        let afterAlive = enemies.filter { $0.isAlive }.count
        let enemiesKilled = beforeAlive - afterAlive

        // Phase 5: Play enemy death sound for each kill
        if enemiesKilled > 0 {
            AudioManager.shared.playSound(AudioManager.SoundEffect.enemyDeath)
        }

        killCount += enemiesKilled
    }

    private func spawnEnemiesInChunks(currentTime: TimeInterval) {
        guard currentTime - lastSpawnTime > Constants.enemySpawnInterval else { return }
        let aliveCount = enemies.filter { $0.isAlive }.count
        guard aliveCount < Constants.maxTotalEnemies else { return }

        lastSpawnTime = currentTime
        let playerChunk = ChunkCoord.containing(worldPosition: player.worldPosition)

        for (coord, chunk) in worldManager.loadedChunks {
            let dist = coord.chebyshevDistance(to: playerChunk)
            guard dist >= 1, dist <= 2 else { continue }

            let chunkEnemyCount = enemies.filter { enemy in
                let ec = ChunkCoord.containing(worldPosition: enemy.worldPosition)
                return ec == coord && enemy.isAlive
            }.count
            guard chunkEnemyCount < Constants.maxEnemiesPerChunk else { continue }

            let positions = chunk.rooms.isEmpty ? chunk.walkablePositions() : chunk.walkableRoomPositions()
            guard !positions.isEmpty else { continue }

            let pick = positions[Int.random(in: 0..<positions.count)]
            let pos = CGPoint(x: CGFloat(pick.worldCol) + 0.5, y: CGFloat(pick.worldRow) + 0.5)

            let distToPlayer = IsometricMath.distance(pos, player.worldPosition)
            guard distToPlayer > 4 else { continue }

            // Scale difficulty by distance from origin + player level
            let enemy = Enemy(worldPosition: pos)
            let distFromOrigin = IsometricMath.distance(pos, .zero)
            let scaling = 1.0 + (distFromOrigin / 20.0) + CGFloat(player.level - 1) * 0.2
            enemy.health = Int(CGFloat(Constants.enemyMaxHealth) * scaling)
            enemy.maxHealth = enemy.health

            enemies.append(enemy)
            worldNode.addChild(enemy.node)

            enemy.node.setScale(0)
            enemy.node.run(SKAction.scale(to: 1.0, duration: 0.3))
            break
        }
    }

    private func removeEnemies(inChunk coord: ChunkCoord) {
        enemies.removeAll { enemy in
            let ec = ChunkCoord.containing(worldPosition: enemy.worldPosition)
            if ec == coord {
                enemy.node.removeFromParent()
                return true
            }
            return false
        }
    }

    // MARK: - XP Collection

    private func collectXPOrbs() {
        let playerScreenPos = player.node.position
        worldNode.enumerateChildNodes(withName: "xpOrb_*") { [weak self] node, _ in
            guard let self = self else { return }
            let dist = IsometricMath.distance(node.position, playerScreenPos)
            if dist < 25 {
                if let name = node.name, let xpStr = name.split(separator: "_").last,
                   let xp = Int(xpStr) {
                    // Phase 5: Play XP gain sound
                    AudioManager.shared.playSound(AudioManager.SoundEffect.xpGain, volume: 0.6)

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
        itemSpawner.removeAll()

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

        let biomeText = worldManager.biomeAt(worldPosition: player.worldPosition)
            .map { "\($0)" } ?? "unknown"
        let statsLabel = SKLabelNode(fontNamed: "Helvetica")
        statsLabel.text = "Level \(player.level) | Kills: \(killCount) | Biome: \(biomeText)"
        statsLabel.fontSize = 16
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

    // MARK: - Touch

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
            self?.showCharacterStats()
        }

        pauseMenu.onSettings = { [weak self] in
            self?.showSettings()
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

    private func showCharacterStats() {
        guard let view = view else { return }

        let characterScreen = CharacterStatsScreen(
            screenSize: view.bounds.size,
            player: player
        )

        characterScreen.onClose = { [weak self] in
            self?.screenManager.dismissModal(animated: true)
        }

        screenManager.showModal(characterScreen, animated: true)
    }

    private func showSettings() {
        guard let view = view else { return }

        let settingsScreen = SettingsScreen(screenSize: view.bounds.size)

        settingsScreen.onClose = { [weak self] in
            self?.screenManager.dismissModal(animated: true)
        }

        settingsScreen.onSettingsChanged = { [weak self] settings in
            // Apply settings
            self?.view?.showsFPS = settings.showFPS
            if settings.showMinimap {
                self?.enhancedHUD.showMinimap()
            } else {
                self?.enhancedHUD.hideMinimap()
            }
        }

        screenManager.showModal(settingsScreen, animated: true)
    }

    private func returnToMainMenu() {
        guard let view = view else { return }

        // Transition back to main menu
        let mainMenu = MainMenuScreen(size: view.bounds.size)
        mainMenu.scaleMode = .resizeFill
        view.presentScene(mainMenu, transition: SKTransition.fade(withDuration: UITheme.animationSlow))
    }
}
