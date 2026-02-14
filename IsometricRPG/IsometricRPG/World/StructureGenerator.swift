import CoreGraphics

/// Generates procedural structures for chunks
enum StructureGenerator {

    /// Generate structures for a chunk based on biome and seed
    static func generateStructures(
        seed: UInt64,
        biome: Biome,
        elevation: [[Int]],
        existingRooms: [Room]
    ) -> [Structure] {
        var rng = SeededRNG(seed: seed &+ 0x5TRUCTUR3)
        var structures: [Structure] = []

        // Filter templates by biome
        let validTemplates = StructureTemplates.all.filter {
            $0.biomes.contains(biome)
        }

        // Calculate structure budget for this chunk
        let budget = structureBudget(for: biome, rng: &rng)

        // Weighted random selection and placement
        var remainingBudget = budget
        while remainingBudget > 0 && rng.nextFloat() < 0.6 {
            guard let template = weightedRandomTemplate(
                from: validTemplates,
                rng: &rng
            ) else { break }

            // Find valid placement
            if let placement = findPlacement(
                template: template,
                elevation: elevation,
                existing: structures,
                rooms: existingRooms,
                rng: &rng
            ) {
                structures.append(placement)
                remainingBudget -= 1

                // Handle clustering (Phase 5)
                if let clusterSize = template.clusterSize, clusterSize > 1 {
                    structures.append(contentsOf: placeCluster(
                        around: placement,
                        template: template,
                        count: clusterSize - 1,
                        elevation: elevation,
                        existing: structures,
                        rooms: existingRooms,
                        rng: &rng
                    ))
                }
            }
        }

        return structures
    }

    // MARK: - Structure Budget

    private static func structureBudget(for biome: Biome, rng: inout SeededRNG) -> Int {
        switch biome {
        case .forest:
            return 8 + Int(rng.next() % 5)  // 8-12 structures
        case .desert:
            return 3 + Int(rng.next() % 3)  // 3-5 structures
        case .dungeon:
            return 0  // Dungeons use room system, no structures
        case .swamp:
            return 5 + Int(rng.next() % 3)  // 5-7 structures
        case .snow:
            return 4 + Int(rng.next() % 3)  // 4-6 structures
        }
    }

    // MARK: - Template Selection

    private static func weightedRandomTemplate(
        from templates: [StructureTemplate],
        rng: inout SeededRNG
    ) -> StructureTemplate? {
        guard !templates.isEmpty else { return nil }

        let totalWeight = templates.reduce(0) { $0 + $1.spawnWeight }
        var random = rng.nextFloat() * totalWeight

        for template in templates {
            random -= template.spawnWeight
            if random <= 0 {
                return template
            }
        }

        return templates.last
    }

    // MARK: - Placement Validation

    private static func findPlacement(
        template: StructureTemplate,
        elevation: [[Int]],
        existing: [Structure],
        rooms: [Room],
        rng: inout SeededRNG
    ) -> Structure? {
        let maxAttempts = 30
        let size = Constants.chunkSize

        for _ in 0..<maxAttempts {
            let x = Int(rng.next() % UInt64(max(size - template.size.width, 1)))
            let y = Int(rng.next() % UInt64(max(size - template.size.height, 1)))

            // Check 1: Doesn't overlap existing structures
            let candidate = Structure(
                template: template,
                x: x, y: y,
                rotation: 0,
                seed: rng.next()
            )
            if existing.contains(where: { candidate.overlaps($0) }) {
                continue
            }

            // Check 2: Doesn't overlap dungeon rooms
            if rooms.contains(where: { candidate.overlaps($0) }) {
                continue
            }

            // Check 3: Elevation constraints
            if !meetsElevationRequirements(
                template: template,
                x: x, y: y,
                elevation: elevation
            ) {
                continue
            }

            // Check 4: Flatness requirement
            if template.requiresFlat && !isFlat(
                x: x, y: y,
                width: template.size.width,
                height: template.size.height,
                elevation: elevation
            ) {
                continue
            }

            // Valid placement found
            let rotation = Int(rng.next() % 4) * 90
            return Structure(
                template: template,
                x: x, y: y,
                rotation: rotation,
                seed: rng.next()
            )
        }

        return nil
    }

    private static func meetsElevationRequirements(
        template: StructureTemplate,
        x: Int, y: Int,
        elevation: [[Int]]
    ) -> Bool {
        // Get average elevation of structure footprint
        var totalElev = 0
        var count = 0
        for row in y..<min(y + template.size.height, elevation.count) {
            for col in x..<min(x + template.size.width, elevation[0].count) {
                totalElev += elevation[row][col]
                count += 1
            }
        }
        guard count > 0 else { return false }
        let avgElev = totalElev / count

        // Check min elevation
        if let minElev = template.minElevation, avgElev < minElev {
            return false
        }

        // Check max elevation
        if let maxElev = template.maxElevation, avgElev > maxElev {
            return false
        }

        return true
    }

    private static func isFlat(
        x: Int, y: Int,
        width: Int, height: Int,
        elevation: [[Int]]
    ) -> Bool {
        guard y >= 0 && x >= 0 &&
              y < elevation.count && x < elevation[0].count else {
            return false
        }

        let baseElev = elevation[y][x]
        for row in y..<min(y + height, elevation.count) {
            for col in x..<min(x + width, elevation[0].count) {
                if abs(elevation[row][col] - baseElev) > Constants.flatnessThreshold {
                    return false
                }
            }
        }
        return true
    }

    // MARK: - Clustering (Phase 5)

    private static func placeCluster(
        around anchor: Structure,
        template: StructureTemplate,
        count: Int,
        elevation: [[Int]],
        existing: [Structure],
        rooms: [Room],
        rng: inout SeededRNG
    ) -> [Structure] {
        var cluster: [Structure] = []
        let radius = 8  // Cluster within 8 tiles

        for _ in 0..<count {
            // Find position near anchor
            let angle = CGFloat(rng.nextFloat()) * .pi * 2
            let distance = CGFloat(2 + Int(rng.next() % UInt64(radius - 2)))
            let offsetX = Int(cos(angle) * distance)
            let offsetY = Int(sin(angle) * distance)

            let x = anchor.x + offsetX
            let y = anchor.y + offsetY

            // Validate bounds
            guard x >= 0 && y >= 0 &&
                  x + template.size.width <= Constants.chunkSize &&
                  y + template.size.height <= Constants.chunkSize else {
                continue
            }

            // Check placement validity
            let candidate = Structure(
                template: template,
                x: x, y: y,
                rotation: Int(rng.next() % 4) * 90,
                seed: rng.next()
            )

            // Check overlaps
            if existing.contains(where: { candidate.overlaps($0) }) {
                continue
            }
            if cluster.contains(where: { candidate.overlaps($0) }) {
                continue
            }
            if rooms.contains(where: { candidate.overlaps($0) }) {
                continue
            }

            // Check elevation requirements
            if !meetsElevationRequirements(
                template: template,
                x: x, y: y,
                elevation: elevation
            ) {
                continue
            }

            // Check flatness
            if template.requiresFlat && !isFlat(
                x: x, y: y,
                width: template.size.width,
                height: template.size.height,
                elevation: elevation
            ) {
                continue
            }

            cluster.append(candidate)
        }

        return cluster
    }

    // MARK: - Advanced Placement (Phase 5)

    static func findHighGround(
        elevation: [[Int]],
        rng: inout SeededRNG
    ) -> (x: Int, y: Int)? {
        // Find positions with elevation > 100
        var highPositions: [(Int, Int)] = []
        for row in 0..<elevation.count {
            for col in 0..<elevation[0].count {
                if elevation[row][col] > 100 {
                    highPositions.append((col, row))
                }
            }
        }

        guard !highPositions.isEmpty else { return nil }
        let index = Int(rng.next() % UInt64(highPositions.count))
        return highPositions[index]
    }
}
