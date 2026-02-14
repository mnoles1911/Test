import CoreGraphics

enum Constants {
    // MARK: - Tile Map
    static let tileWidth: CGFloat = 64
    static let tileHeight: CGFloat = 32
    static let mapColumns = 20
    static let mapRows = 20

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
    static let maxEnemies = 10
    static let enemySpawnInterval: TimeInterval = 3.0

    // MARK: - Input
    static let joystickRadius: CGFloat = 50
    static let joystickKnobRadius: CGFloat = 20
    static let joystickDeadZone: CGFloat = 0.1

    // MARK: - Z Ordering
    enum ZPosition {
        static let tile: CGFloat = 0
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
