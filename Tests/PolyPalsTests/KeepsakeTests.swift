import Foundation
import SwiftData
import Testing
@testable import PolyPals

@Suite("Gifts, found keepsakes, and quiet state")
struct KeepsakeTests {
    @Test("Every pet has a unique offline keepsake pool")
    func catalogCoverage() {
        for petID in PetID.allCases {
            let items = PetKeepsakeCatalog.items(for: petID)
            #expect(items.count >= 8)
            #expect(Set(items.map(\.key)).count == items.count)
            #expect(items.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty && !$0.symbol.isEmpty })
        }
    }

    @Test("Found keepsakes require interaction, respect unread cap, and appear at most once per day")
    func foundPolicy() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        #expect(!PetFoundItemPolicy.shouldCreate(petID: .sol, now: now, lastFoundAt: nil, hasInteracted: false, unreadCount: 0, calendar: calendar))
        #expect(!PetFoundItemPolicy.shouldCreate(petID: .sol, now: now, lastFoundAt: nil, hasInteracted: true, unreadCount: 3, calendar: calendar))

        let dayStart = calendar.startOfDay(for: now)
        let laterThatDay = dayStart.addingTimeInterval(20 * 60 * 60)
        let sameDay = dayStart.addingTimeInterval(60 * 60)
        #expect(!PetFoundItemPolicy.shouldCreate(petID: .sol, now: laterThatDay, lastFoundAt: sameDay, hasInteracted: true, unreadCount: 0, calendar: calendar))

        let decisions = (0..<7).map { offset in
            PetFoundItemPolicy.shouldCreate(
                petID: .sol,
                now: calendar.date(byAdding: .day, value: offset, to: now)!,
                lastFoundAt: nil,
                hasInteracted: true,
                unreadCount: 0,
                calendar: calendar
            )
        }
        #expect(decisions.filter { $0 }.count >= 4)
        #expect(decisions.contains(false))
    }

    @Test("Version 5 stores inventory story and per-pet quiet state")
    @MainActor
    func persistence() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let item = InventoryItemEntity(petID: .mousse, kind: "found", title: "小菜单", detail: "Un petit menu")
        context.insert(item)
        context.insert(InventoryStoryEntity(itemID: item.id, petID: .mousse, origin: .petFound, contentKey: "mousse-menu", symbol: "menucard", isUnread: true))
        context.insert(PetQuietStateEntity(petID: .mousse, quietUntil: Date().addingTimeInterval(3600)))
        try context.save()

        let stories = try context.fetch(FetchDescriptor<InventoryStoryEntity>())
        let quietStates = try context.fetch(FetchDescriptor<PetQuietStateEntity>())
        #expect(stories.first?.origin == InventoryOrigin.petFound.rawValue)
        #expect(stories.first?.isUnread == true)
        #expect(quietStates.first?.petID == PetID.mousse.rawValue)
        #expect(quietStates.first?.quietUntil != nil)
    }

    @Test("Version 4 store migrates to V5 without losing inventory")
    @MainActor
    func v4Migration() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("polypals-v4-to-v5-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }

        do {
            let schema = Schema(versionedSchema: PolyPalsSchemaV4.self)
            let configuration = SwiftData.ModelConfiguration(schema: schema, url: url)
            let old = try ModelContainer(for: schema, configurations: configuration)
            old.mainContext.insert(PetProfileEntity(definition: .definition(for: .sol)))
            old.mainContext.insert(InventoryItemEntity(petID: .sol, kind: "gift", title: "旧礼物", detail: "保留我"))
            try old.mainContext.save()
        }

        let migrated = try PersistenceFactory.makeContainer(at: url)
        let items = try migrated.mainContext.fetch(FetchDescriptor<InventoryItemEntity>())
        #expect(items.count == 1)
        #expect(items.first?.title == "旧礼物")
        migrated.mainContext.insert(PetQuietStateEntity(petID: .sol, quietUntil: Date().addingTimeInterval(60)))
        try migrated.mainContext.save()
        #expect(try migrated.mainContext.fetch(FetchDescriptor<PetQuietStateEntity>()).count == 1)
    }
}
