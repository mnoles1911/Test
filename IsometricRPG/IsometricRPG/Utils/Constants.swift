import CoreGraphics

enum Constants {
    // MARK: - World Seed
    static let worldSeed: UInt64 = 42

    // MARK: - Chunks
    static let chunkSize = 16          // tiles per chunk edge
    static let loadRadius = 3          // chunks to load around player
    static let unloadRadius = 5        // chunks beyond this get removed

    // MARK: - Tile Rendering
    static let tileWidth: CGFloat = 64
    static let tileHeight: CGFloat = 32

    // MARK: - Elevation
    static let elevationHeightMultiplier: CGFloat = 0.5
    static let maxWalkableElevationDiff = 5
    static let cliffThreshold = 10
    static let flatnessThreshold = 3

    // MARK: - Dungeon Generation
    static let roomMinSize = 4
    static let roomMaxSize = 8
    static let roomsPerChunk = 3
    static let corridorWidth = 2

    // MARK: - Player
    static let playerSpeed: CGFloat = 150
    static let playerMaxHealth: Int = 100
    static let playerSize = CGSize(width: 20, height: 28)

    // MARK: - Combat
    static let bulletSpeed: CGFloat = 400
    static let bulletDamage: Int = 25
    static let fireRate: TimeInterval = 0.25
    static let bulletLifetime: TimeInterval = 2.0

    // MARK: - Enemies
    static let enemySpeed: CGFloat = 60
    static let enemyMaxHealth: Int = 50
    static let enemySize = CGSize(width: 18, height: 24)
    static let enemyDetectionRange: CGFloat = 200
    static let enemyAttackRange: CGFloat = 30
    static let enemyAttackDamage: Int = 10
    static let enemyAttackCooldown: TimeInterval = 1.0
    static let maxEnemiesPerChunk = 3
    static let maxTotalEnemies = 20
    static let enemySpawnInterval: TimeInterval = 2.0

    // MARK: - Items
    static let itemPickupRange: CGFloat = 0.8
    static let itemAttractRange: CGFloat = 2.5
    static let itemAttractSpeed: CGFloat = 3.0
    static let maxItemsPerChunk = 4

    // MARK: - Input
    static let joystickRadius: CGFloat = 50
    static let joystickKnobRadius: CGFloat = 20
    static let joystickDeadZone: CGFloat = 0.1

    // MARK: - Z Ordering
    enum ZPosition {
        static let tile: CGFloat = 0
        static let item: CGFloat = 4
        static let shadow: CGFloat = 5
        static let entity: CGFloat = 10
        static let bullet: CGFloat = 15
        static let hud: CGFloat = 100
        static let overlay: CGFloat = 150
        static let modal: CGFloat = 200
        static let modalContent: CGFloat = 210
    }

    // MARK: - Physics Categories
    enum PhysicsCategory {
        static let none: UInt32       = 0
        static let player: UInt32     = 0b0001
        static let enemy: UInt32      = 0b0010
        static let bullet: UInt32     = 0b0100
        static let wall: UInt32       = 0b1000
    }
}
