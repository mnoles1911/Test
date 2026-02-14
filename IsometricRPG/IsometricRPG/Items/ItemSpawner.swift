import SpriteKit

/// Responsible for placing items into newly loaded chunks based on triggers and loot tables.
final class ItemSpawner {
    private(set) var worldItems: [WorldItem] = []
    private weak var worldNode: SKNode?

    init(worldNode: SKNode) {
        self.worldNode = worldNode
    }

    // MARK: - Spawn Items for a Chunk

    /// Evaluate all triggers, build a weighted loot table, and spawn items in the chunk.
    func spawnItems(in chunk: Chunk, context: GameContext) {
        guard !chunk.spawnedItems else { return }
        chunk.spawnedItems = true

        // Collect walkable positions for item placement
        let positions: [(worldCol: Int, worldRow: Int)]
        if !chunk.rooms.isEmpty {
            positions = chunk.walkableRoomPositions()
        } else {
            positions = chunk.walkablePositions()
        }

        guard !positions.isEmpty else { return }

        // Build weighted loot table
        var weights: [ItemType: Float] = [:]
        for item in ItemType.allCases {
            weights[item] = item.baseWeight
        }

        // Apply all active triggers
        var bonusCount = 0
        for trigger in SpawnTriggerRegistry.allTriggers {
            if trigger.shouldFire(context: context) {
                for (item, multiplier) in trigger.weightModifiers {
                    weights[item, default: item.baseWeight] *= multiplier
                }
                bonusCount += trigger.spawnCountBonus
            }
        }

        // Determine spawn count
        var rng = SeededRNG(seed: chunk.coord.chunkSeed &+ 0x14E3)
        let baseCount = chunk.rooms.isEmpty ? 1 : min(chunk.rooms.count, Constants.maxItemsPerChunk)
        let totalCount = min(baseCount + bonusCount, Constants.maxItemsPerChunk)

        // Weighted random selection
        var shuffledPositions = positions
        // Fisher-Yates shuffle with seeded RNG
        for i in stride(from: shuffledPositions.count - 1, through: 1, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            shuffledPositions.swapAt(i, j)
        }

        for i in 0..<min(totalCount, shuffledPositions.count) {
            let itemType = weightedRandomItem(weights: weights, rng: &rng)
            let pos = shuffledPositions[i]
            let worldPos = CGPoint(x: CGFloat(pos.worldCol) + 0.5,
                                   y: CGFloat(pos.worldRow) + 0.5)
            let item = WorldItem(itemType: itemType, worldPosition: worldPos)
            worldItems.append(item)
            worldNode?.addChild(item.node)
        }
    }

    // MARK: - Item Collection

    /// Check proximity and collect items near the player.
    func collectItems(near player: Player) {
        let playerPos = player.worldPosition

        for item in worldItems where !item.isPickedUp {
            let dist = IsometricMath.distance(item.worldPosition, playerPos)

            if dist < Constants.itemPickupRange {
                item.applyEffect(to: player)
                item.pickup()
                showPickupText(item.itemType.displayName, at: item.node.position)
            } else if dist < Constants.itemAttractRange {
                // Attract toward player
                let dir = IsometricMath.direction(from: item.worldPosition, to: playerPos)
                let attractSpeed = Constants.itemAttractSpeed * (1.0 / 60.0)
                item.worldPosition = CGPoint(
                    x: item.worldPosition.x + dir.x * attractSpeed,
                    y: item.worldPosition.y + dir.y * attractSpeed
                )
                item.syncPosition()
            }
        }

        // Clean up collected items
        worldItems.removeAll { $0.isPickedUp && $0.node.parent == nil }
    }

    // MARK: - Cleanup

    /// Remove items belonging to unloaded chunks.
    func removeItems(inChunk coord: ChunkCoord) {
        let originCol = CGFloat(coord.worldOriginCol)
        let originRow = CGFloat(coord.worldOriginRow)
        let size = CGFloat(Constants.chunkSize)

        let toRemove = worldItems.filter { item in
            let x = item.worldPosition.x
            let y = item.worldPosition.y
            return x >= originCol && x < originCol + size &&
                   y >= originRow && y < originRow + size
        }

        for item in toRemove {
            item.node.removeFromParent()
        }
        worldItems.removeAll { item in
            let x = item.worldPosition.x
            let y = item.worldPosition.y
            return x >= originCol && x < originCol + size &&
                   y >= originRow && y < originRow + size
        }
    }

    func removeAll() {
        for item in worldItems {
            item.node.removeFromParent()
        }
        worldItems.removeAll()
    }

    // MARK: - Helpers

    private func weightedRandomItem(weights: [ItemType: Float], rng: inout SeededRNG) -> ItemType {
        let totalWeight = weights.values.reduce(0, +)
        var roll = Float(rng.next() % 10000) / 10000.0 * totalWeight
        for (item, weight) in weights {
            roll -= weight
            if roll <= 0 {
                return item
            }
        }
        return .healthPotion // fallback
    }

    private func showPickupText(_ text: String, at position: CGPoint) {
        guard let parent = worldNode else { return }
        let label = SKLabelNode(fontNamed: "Helvetica-Bold")
        label.text = text
        label.fontSize = 10
        label.fontColor = .white
        label.position = position
        label.zPosition = Constants.ZPosition.entity + 5
        parent.addChild(label)

        let rise = SKAction.moveBy(x: 0, y: 25, duration: 0.8)
        let fade = SKAction.fadeOut(withDuration: 0.6)
        label.run(SKAction.sequence([
            SKAction.group([rise, fade]),
            SKAction.removeFromParent()
        ]))
    }
}
