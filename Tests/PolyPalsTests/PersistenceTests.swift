import Foundation
import SwiftData
import Testing
@testable import PolyPals

@Suite("Persistence")
struct PersistenceTests {
    @Test("New pets use natural-pause behavior by default")
    func naturalPauseDefault() {
        let profile = PetProfileEntity(definition: .definition(for: .sol))
        #expect(profile.proactiveMode == ProactiveMode.naturalPause.rawValue)
    }

    @Test("Version 1 store migrates without losing pet data")
    @MainActor
    func v1Migration() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("polypals-migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }

        do {
            let schema = Schema(versionedSchema: PolyPalsSchemaV1.self)
            let configuration = SwiftData.ModelConfiguration(schema: schema, url: url)
            let oldContainer = try ModelContainer(for: schema, configurations: configuration)
            let oldProfile = PolyPalsSchemaV1.PetProfileEntity()
            oldProfile.petID = PetID.sol.rawValue
            oldProfile.name = "Sol"
            oldProfile.targetLanguage = "es"
            oldProfile.difficulty = "B1"
            oldProfile.relationshipPoints = 37
            oldContainer.mainContext.insert(oldProfile)
            try oldContainer.mainContext.save()
        }

        let schema = Schema(versionedSchema: PolyPalsSchemaV2.self)
        let configuration = SwiftData.ModelConfiguration(schema: schema, url: url)
        let migrated = try ModelContainer(
            for: schema,
            migrationPlan: PolyPalsMigrationPlan.self,
            configurations: configuration
        )
        let profiles = try migrated.mainContext.fetch(FetchDescriptor<PetProfileEntity>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.petID == PetID.sol.rawValue)
        #expect(profiles.first?.relationshipPoints == 37)
    }

    @Test("Version 2 store opens as v3 with companion records")
    @MainActor
    func v2ToV3Migration() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("polypals-v2-to-v3-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }

        let v2Schema = Schema(versionedSchema: PolyPalsSchemaV2.self)
        let v2Configuration = SwiftData.ModelConfiguration(schema: v2Schema, url: url)
        let old = try ModelContainer(for: v2Schema, configurations: v2Configuration)
        let profile = PetProfileEntity(definition: .definition(for: .ash))
        profile.relationshipPoints = 75
        old.mainContext.insert(profile)
        try old.mainContext.save()

        let migrated = try PersistenceFactory.makeContainer(at: url)
        let profiles = try migrated.mainContext.fetch(FetchDescriptor<PetProfileEntity>())
        let metadata = try migrated.mainContext.fetch(FetchDescriptor<PetProfileMetadataEntity>())
        #expect(profiles.first?.relationshipPoints == 75)
        #expect(metadata.count == 1)
        #expect(metadata.first?.petID == PetID.ash.rawValue)
        #expect(metadata.first?.highestRelationshipLevelSeen == 4)
    }

    @Test("In-memory schema stores independent pets")
    @MainActor
    func partitioning() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(PetProfileEntity(definition: .definition(for: .sol)))
        context.insert(PetProfileEntity(definition: .definition(for: .mousse)))
        context.insert(PetMemoryEntity(petID: .sol, type: "topic", content: "喜欢天文学", importance: 3))
        try context.save()
        let memories = try context.fetch(FetchDescriptor<PetMemoryEntity>())
        #expect(memories.count == 1)
        #expect(memories.first?.petID == PetID.sol.rawValue)
    }
}
