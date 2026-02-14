import Foundation

/// Registry of all structure templates
enum StructureTemplates {

    // MARK: - Environmental Structures

    static let tree = StructureTemplate(
        type: .tree,
        category: .decoration,
        size: (width: 1, height: 1),
        footprint: [[.grass]],
        elevationProfile: [[1]],
        spawnWeight: 10.0,
        biomes: [.forest, .swamp],
        minElevation: 20,
        maxElevation: 150,
        requiresFlat: false,
        clusterSize: 3
    )

    static let rock = StructureTemplate(
        type: .rock,
        category: .decoration,
        size: (width: 1, height: 1),
        footprint: [[.stone]],
        elevationProfile: [[2]],
        spawnWeight: 8.0,
        biomes: [.forest, .desert, .snow],
        minElevation: 50,
        maxElevation: 200,
        requiresFlat: false,
        clusterSize: nil
    )

    static let bush = StructureTemplate(
        type: .bush,
        category: .decoration,
        size: (width: 1, height: 1),
        footprint: [[.grass]],
        elevationProfile: nil,
        spawnWeight: 7.0,
        biomes: [.forest, .swamp],
        minElevation: 20,
        maxElevation: 120,
        requiresFlat: false,
        clusterSize: 2
    )

    static let cactus = StructureTemplate(
        type: .cactus,
        category: .decoration,
        size: (width: 1, height: 1),
        footprint: [[.sand]],
        elevationProfile: [[2]],
        spawnWeight: 8.0,
        biomes: [.desert],
        minElevation: 40,
        maxElevation: 100,
        requiresFlat: false,
        clusterSize: 2
    )

    static let log = StructureTemplate(
        type: .log,
        category: .decoration,
        size: (width: 2, height: 1),
        footprint: [[.dirt, .dirt]],
        elevationProfile: nil,
        spawnWeight: 5.0,
        biomes: [.forest, .swamp],
        minElevation: nil,
        maxElevation: nil,
        requiresFlat: true,
        clusterSize: nil
    )

    // MARK: - Buildings

    static let house = StructureTemplate(
        type: .house,
        category: .building,
        size: (width: 3, height: 3),
        footprint: [
            [.wall, .wall, .wall],
            [.wall, .dungeonFloor, .doorway],
            [.wall, .wall, .wall]
        ],
        elevationProfile: nil,
        spawnWeight: 2.0,
        biomes: [.forest, .snow],
        minElevation: nil,
        maxElevation: nil,
        requiresFlat: true,
        clusterSize: 5
    )

    static let shop = StructureTemplate(
        type: .shop,
        category: .building,
        size: (width: 4, height: 4),
        footprint: [
            [.wall, .wall, .wall, .wall],
            [.wall, .dungeonFloor, .dungeonFloor, .wall],
            [.wall, .dungeonFloor, .dungeonFloor, .doorway],
            [.wall, .wall, .wall, .wall]
        ],
        elevationProfile: nil,
        spawnWeight: 1.5,
        biomes: [.forest],
        minElevation: nil,
        maxElevation: 100,
        requiresFlat: true,
        clusterSize: nil
    )

    static let tower = StructureTemplate(
        type: .tower,
        category: .building,
        size: (width: 2, height: 2),
        footprint: [
            [.stone, .stone],
            [.stone, .stone]
        ],
        elevationProfile: [
            [5, 5],
            [5, 5]
        ],
        spawnWeight: 1.0,
        biomes: [.forest, .desert, .snow],
        minElevation: 80,
        maxElevation: 200,
        requiresFlat: false,
        clusterSize: nil
    )

    static let ruin = StructureTemplate(
        type: .ruin,
        category: .building,
        size: (width: 4, height: 4),
        footprint: [
            [.stone, .wall, .wall, .stone],
            [.wall, .dirt, .dirt, .wall],
            [.wall, .dirt, .stone, .dirt],
            [.stone, .wall, .dirt, .stone]
        ],
        elevationProfile: nil,
        spawnWeight: 2.0,
        biomes: [.desert, .swamp],
        minElevation: nil,
        maxElevation: nil,
        requiresFlat: true,
        clusterSize: nil
    )

    static let inn = StructureTemplate(
        type: .inn,
        category: .building,
        size: (width: 5, height: 5),
        footprint: [
            [.wall, .wall, .wall, .wall, .wall],
            [.wall, .dungeonFloor, .dungeonFloor, .dungeonFloor, .wall],
            [.wall, .dungeonFloor, .dungeonFloor, .dungeonFloor, .doorway],
            [.wall, .dungeonFloor, .dungeonFloor, .dungeonFloor, .wall],
            [.wall, .wall, .wall, .wall, .wall]
        ],
        elevationProfile: nil,
        spawnWeight: 0.8,
        biomes: [.forest],
        minElevation: nil,
        maxElevation: 90,
        requiresFlat: true,
        clusterSize: nil
    )

    // MARK: - Camps

    static let shrine = StructureTemplate(
        type: .shrine,
        category: .camp,
        size: (width: 2, height: 2),
        footprint: [
            [.stone, .stone],
            [.stone, .stone]
        ],
        elevationProfile: [[1, 1], [1, 1]],
        spawnWeight: 1.2,
        biomes: [.forest, .swamp, .snow],
        minElevation: nil,
        maxElevation: 50,
        requiresFlat: true,
        clusterSize: nil
    )

    static let banditCamp = StructureTemplate(
        type: .banditCamp,
        category: .camp,
        size: (width: 3, height: 3),
        footprint: [
            [.dirt, .dirt, .dirt],
            [.dirt, .dirt, .dirt],
            [.dirt, .dirt, .dirt]
        ],
        elevationProfile: nil,
        spawnWeight: 1.5,
        biomes: [.forest, .desert],
        minElevation: nil,
        maxElevation: nil,
        requiresFlat: true,
        clusterSize: nil
    )

    // MARK: - Treasures

    static let chest = StructureTemplate(
        type: .chest,
        category: .treasure,
        size: (width: 1, height: 1),
        footprint: [[.dungeonFloor]],
        elevationProfile: nil,
        spawnWeight: 2.0,
        biomes: [.forest, .desert, .swamp, .snow],
        minElevation: nil,
        maxElevation: nil,
        requiresFlat: false,
        clusterSize: nil
    )

    static let altar = StructureTemplate(
        type: .altar,
        category: .treasure,
        size: (width: 2, height: 2),
        footprint: [
            [.stone, .stone],
            [.stone, .stone]
        ],
        elevationProfile: [[2, 2], [2, 2]],
        spawnWeight: 0.5,
        biomes: [.forest, .swamp, .snow],
        minElevation: nil,
        maxElevation: nil,
        requiresFlat: true,
        clusterSize: nil
    )

    // MARK: - Fortifications

    static let watchtower = StructureTemplate(
        type: .watchtower,
        category: .fortification,
        size: (width: 3, height: 3),
        footprint: [
            [.stone, .stone, .stone],
            [.stone, .dungeonFloor, .stone],
            [.stone, .stone, .stone]
        ],
        elevationProfile: [
            [4, 4, 4],
            [4, 0, 4],
            [4, 4, 4]
        ],
        spawnWeight: 1.0,
        biomes: [.forest, .desert, .snow],
        minElevation: 100,
        maxElevation: 200,
        requiresFlat: false,
        clusterSize: nil
    )

    // MARK: - All Templates

    static let all: [StructureTemplate] = [
        tree, rock, bush, cactus, log,
        house, shop, tower, ruin, inn,
        shrine, banditCamp,
        chest, altar,
        watchtower
    ]
}
