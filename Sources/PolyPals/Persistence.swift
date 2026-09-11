import Foundation
import SwiftData

@Model
final class PetProfileEntity {
    @Attribute(.unique) var petID: String
    var name: String
    var targetLanguage: String
    var difficulty: String
    var languageRatio: Double
    var correctionMode: String
    var proactiveMode: String
    var quietStartHour: Int
    var quietEndHour: Int
    var isVisible: Bool
    var isSleeping: Bool
    var appearsOnAllSpaces: Bool
    var size: Double
    var relationshipPoints: Int
    var savesChatHistory: Bool
    var notificationEnabled: Bool
    var preferredVoiceIdentifier: String?
    var lastInteractionAt: Date?
    var firstMetAt: Date = Date()
    var highestRelationshipLevelSeen: Int = 1

    init(definition: PetDefinition) {
        petID = definition.id.rawValue
        name = definition.name
        targetLanguage = definition.targetLanguage
        difficulty = definition.level
        languageRatio = definition.languageRatio
        correctionMode = CorrectionMode.casual.rawValue
        proactiveMode = ProactiveMode.naturalPause.rawValue
        quietStartHour = 22
        quietEndHour = 9
        isVisible = true
        isSleeping = false
        appearsOnAllSpaces = false
        size = 128
        relationshipPoints = 0
        savesChatHistory = true
        notificationEnabled = false
        lastInteractionAt = nil
        firstMetAt = Date()
        highestRelationshipLevelSeen = 1
    }
}

@Model
final class PetMemoryEntity {
    @Attribute(.unique) var id: UUID
    var petID: String
    var type: String
    var content: String
    var importance: Int
    var source: String
    var createdAt: Date
    var lastUsedAt: Date?
    var userEditable: Bool

    init(petID: PetID, type: String, content: String, importance: Int, source: String = "user-confirmed") {
        id = UUID()
        self.petID = petID.rawValue
        self.type = type
        self.content = content
        self.importance = importance
        self.source = source
        createdAt = Date()
        userEditable = true
    }
}

@Model
final class ChatThreadEntity {
    @Attribute(.unique) var id: UUID
    var petID: String
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(petID: PetID, title: String = "新的聊天") {
        id = UUID()
        self.petID = petID.rawValue
        self.title = title
        createdAt = Date()
        updatedAt = Date()
    }
}

@Model
final class ChatMessageEntity {
    @Attribute(.unique) var id: UUID
    var threadID: UUID
    var petID: String
    var role: String
    var text: String
    var createdAt: Date
    var isFavorite: Bool

    init(threadID: UUID, petID: PetID, role: ChatRole, text: String) {
        id = UUID()
        self.threadID = threadID
        self.petID = petID.rawValue
        self.role = role.rawValue
        self.text = text
        createdAt = Date()
        isFavorite = false
    }
}

@Model
final class InventoryItemEntity {
    @Attribute(.unique) var id: UUID
    var petID: String
    var kind: String
    var title: String
    var detail: String
    var createdAt: Date
    var isFavorite: Bool

    init(petID: PetID, kind: String, title: String, detail: String, isFavorite: Bool = false) {
        id = UUID()
        self.petID = petID.rawValue
        self.kind = kind
        self.title = title
        self.detail = detail
        createdAt = Date()
        self.isFavorite = isFavorite
    }
}

@Model
final class ContentCardEntity {
    @Attribute(.unique) var id: UUID
    var petID: String
    var type: String
    var targetLanguage: String
    var level: String
    var estimatedSeconds: Int
    var encodedContent: Data
    var source: String
    var memoryKey: String
    var createdAt: Date
    var isFavorite: Bool
    var contentFingerprint: String = ""
    var lastPresentedAt: Date?
    var presentationCount: Int = 0

    init(card: GeneratedCard, source: String) throws {
        id = card.id
        petID = card.petID.rawValue
        type = card.type.rawValue
        targetLanguage = card.language
        level = card.level
        estimatedSeconds = card.estimatedSeconds
        encodedContent = try JSONEncoder().encode(card)
        self.source = source
        memoryKey = card.memoryKey
        createdAt = Date()
        isFavorite = false
        contentFingerprint = CardFingerprint.make(card)
        lastPresentedAt = nil
        presentationCount = 0
    }
}

@Model
final class InteractionEntity {
    @Attribute(.unique) var id: UUID
    var petID: String
    var cardID: UUID?
    var startedAt: Date
    var endedAt: Date?
    var skipped: Bool
    var responseType: String?
    var userFeedback: String?
    var memoryKey: String?
    var cardType: String?
    var contentSource: String?

    init(petID: PetID, cardID: UUID? = nil, memoryKey: String? = nil, cardType: CardType? = nil, contentSource: String? = nil) {
        id = UUID()
        self.petID = petID.rawValue
        self.cardID = cardID
        startedAt = Date()
        skipped = false
        self.memoryKey = memoryKey
        self.cardType = cardType?.rawValue
        self.contentSource = contentSource
    }
}

@Model
final class RelationshipEventEntity {
    @Attribute(.unique) var id: UUID
    var petID: String
    var eventType: String
    var day: Date
    var pointsAwarded: Int
    var createdAt: Date

    init(petID: PetID, event: RelationshipEvent, pointsAwarded: Int, now: Date = Date()) {
        id = UUID()
        self.petID = petID.rawValue
        eventType = event.rawValue
        day = Calendar.current.startOfDay(for: now)
        self.pointsAwarded = pointsAwarded
        createdAt = now
    }
}

@Model
final class SchedulerStateEntity {
    @Attribute(.unique) var singletonID: String
    var day: Date
    var lastGlobalInvitationAt: Date?
    var globalInvitationCountToday: Int
    var petCountsJSON: Data
    var rejectedPetsJSON: Data
    var consecutiveDeclines: Int
    var quietUntil: Date?

    init(now: Date = Date()) {
        singletonID = "global"
        day = Calendar.current.startOfDay(for: now)
        globalInvitationCountToday = 0
        petCountsJSON = Data("{}".utf8)
        rejectedPetsJSON = Data("[]".utf8)
        consecutiveDeclines = 0
    }
}

@Model
final class ScheduleEntity {
    @Attribute(.unique) var id: UUID
    var petID: String
    var triggerType: String
    var fireDate: Date?
    var recurrence: String?
    var contentPreference: String
    var isEnabled: Bool
    var quietPolicy: String
    var usesSystemNotification: Bool
    var isCoursePlan: Bool
    var lastTriggeredAt: Date?
    var createdAt: Date

    init(
        petID: PetID,
        trigger: ScheduleTrigger,
        fireDate: Date?,
        recurrence: String?,
        contentPreference: String,
        usesSystemNotification: Bool = false,
        isCoursePlan: Bool = false
    ) {
        id = UUID()
        self.petID = petID.rawValue
        triggerType = trigger.rawValue
        self.fireDate = fireDate
        self.recurrence = recurrence
        self.contentPreference = contentPreference
        isEnabled = true
        quietPolicy = "respect-global"
        self.usesSystemNotification = usesSystemNotification
        self.isCoursePlan = isCoursePlan
        lastTriggeredAt = nil
        createdAt = Date()
    }
}

@Model
final class PetWindowStateEntity {
    @Attribute(.unique) var petID: String
    var displayID: String?
    var normalizedX: Double
    var normalizedY: Double
    var updatedAt: Date

    init(petID: PetID, displayID: String? = nil, normalizedX: Double, normalizedY: Double) {
        self.petID = petID.rawValue
        self.displayID = displayID
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        updatedAt = Date()
    }
}

@Model
final class LocalMetricEntity {
    @Attribute(.unique) var id: UUID
    var petID: String?
    var day: Date
    var name: String
    var count: Int
    var totalDuration: Double

    init(petID: PetID?, day: Date, name: String, count: Int = 1, totalDuration: Double = 0) {
        id = UUID()
        self.petID = petID?.rawValue
        self.day = Calendar.current.startOfDay(for: day)
        self.name = name
        self.count = count
        self.totalDuration = totalDuration
    }
}

// v0.3 companion records. Existing v2 entities remain frozen so their model
// hashes stay migratable for installed users.
@Model
final class PetProfileMetadataEntity {
    @Attribute(.unique) var petID: String
    var firstMetAt: Date
    var highestRelationshipLevelSeen: Int
    var updatedAt: Date

    init(petID: PetID, firstMetAt: Date = Date(), highestRelationshipLevelSeen: Int = 1) {
        self.petID = petID.rawValue
        self.firstMetAt = firstMetAt
        self.highestRelationshipLevelSeen = highestRelationshipLevelSeen
        updatedAt = Date()
    }
}

// Language learning settings live beside the frozen profile entity so adding
// v0.4 fields never changes the model hash used by existing installations.
@Model
final class LanguageProfileEntity {
    @Attribute(.unique) var petID: String
    var targetLanguage: String
    var currentLevel: String
    var receptiveLevel: String
    var productiveLevel: String
    var difficultyMode: String
    var chineseHelpRatio: Double
    var correctionMode: String
    var updatedAt: Date

    init(petID: PetID, profile: LanguageProfile) {
        self.petID = petID.rawValue
        targetLanguage = profile.targetLanguage
        currentLevel = profile.currentLevel.rawValue
        receptiveLevel = profile.receptiveLevel.rawValue
        productiveLevel = profile.productiveLevel.rawValue
        difficultyMode = profile.difficultyMode.rawValue
        chineseHelpRatio = profile.chineseHelpRatio
        correctionMode = profile.correctionMode.rawValue
        updatedAt = Date()
    }

    var value: LanguageProfile {
        LanguageProfile(
            targetLanguage: targetLanguage,
            currentLevel: CEFRLevel.parse(currentLevel),
            receptiveLevel: CEFRLevel.parse(receptiveLevel, default: CEFRLevel.parse(currentLevel)),
            productiveLevel: CEFRLevel.parse(productiveLevel, default: CEFRLevel.parse(currentLevel)),
            difficultyMode: DifficultyMode(rawValue: difficultyMode) ?? .fixed,
            chineseHelpRatio: chineseHelpRatio,
            correctionMode: CorrectionMode(rawValue: correctionMode) ?? .casual
        )
    }

    func update(from profile: LanguageProfile) {
        targetLanguage = profile.targetLanguage
        currentLevel = profile.currentLevel.rawValue
        receptiveLevel = profile.receptiveLevel.rawValue
        productiveLevel = profile.productiveLevel.rawValue
        difficultyMode = profile.difficultyMode.rawValue
        chineseHelpRatio = min(1, max(0, profile.chineseHelpRatio))
        correctionMode = profile.correctionMode.rawValue
        updatedAt = Date()
    }
}

@Model
final class PetRoutineStateEntity {
    @Attribute(.unique) var petID: String
    var lastAmbientAction: String?
    var lastAmbientActionAt: Date?
    var lastNapAt: Date?
    var lastTidyAt: Date?
    var recentActionsJSON: Data
    var updatedAt: Date

    init(petID: PetID) {
        self.petID = petID.rawValue
        recentActionsJSON = Data("[]".utf8)
        updatedAt = Date()
    }
}

@Model
final class PetDailyStateEntity {
    @Attribute(.unique) var petDayKey: String
    var petID: String
    var day: Date
    var napCount: Int
    var walkCount: Int
    var stretchCount: Int
    var tidyCount: Int
    var chatCount: Int
    var completedCardCount: Int
    var giftCount: Int
    var noteworthyMomentKey: String?
    var updatedAt: Date

    init(petID: PetID, day: Date = Date()) {
        self.petID = petID.rawValue
        let normalizedDay = Calendar.current.startOfDay(for: day)
        self.day = normalizedDay
        petDayKey = "\(petID.rawValue)|\(Self.dayFormatter.string(from: normalizedDay))"
        napCount = 0; walkCount = 0; stretchCount = 0; tidyCount = 0
        chatCount = 0; completedCardCount = 0; giftCount = 0
        updatedAt = Date()
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

@Model
final class InventoryEffectEntity {
    @Attribute(.unique) var inventoryItemID: UUID
    var petID: String
    var tagsJSON: Data
    var referenceCount: Int
    var lastReferencedAt: Date?

    init(itemID: UUID, petID: PetID, tags: [String] = []) {
        inventoryItemID = itemID; self.petID = petID.rawValue
        tagsJSON = (try? JSONEncoder().encode(tags)) ?? Data("[]".utf8)
        referenceCount = 0
    }
}

@Model
final class InventoryStoryEntity {
    @Attribute(.unique) var inventoryItemID: UUID
    var petID: String
    var origin: String
    var contentKey: String?
    var symbol: String
    var isUnread: Bool
    var revealedAt: Date?

    init(itemID: UUID, petID: PetID, origin: InventoryOrigin, contentKey: String? = nil, symbol: String = "shippingbox", isUnread: Bool = false) {
        inventoryItemID = itemID
        self.petID = petID.rawValue
        self.origin = origin.rawValue
        self.contentKey = contentKey
        self.symbol = symbol
        self.isUnread = isUnread
    }
}

@Model
final class PetQuietStateEntity {
    @Attribute(.unique) var petID: String
    var quietUntil: Date?
    var includesSchedules: Bool
    var updatedAt: Date

    init(petID: PetID, quietUntil: Date? = nil, includesSchedules: Bool = false) {
        self.petID = petID.rawValue
        self.quietUntil = quietUntil
        self.includesSchedules = includesSchedules
        updatedAt = Date()
    }
}

@Model
final class CardMetadataEntity {
    @Attribute(.unique) var metadataKey: String
    var petID: String
    var memoryKey: String
    var contentFingerprint: String
    var tagsJSON: Data
    var conceptKey: String
    var originMemoryKey: String?
    var modality: String
    var challenge: Int
    var qualityScore: Int
    var isHidden: Bool
    var packID: String?
    var lastPresentedAt: Date?
    var presentationCount: Int
    var updatedAt: Date

    init(card: GeneratedCard, packID: String? = nil, qualityScore: Int = 100) {
        metadataKey = "\(card.petID.rawValue)|\(card.memoryKey)"
        petID = card.petID.rawValue; memoryKey = card.memoryKey
        contentFingerprint = CardFingerprint.make(card)
        tagsJSON = (try? JSONEncoder().encode(card.tags)) ?? Data("[]".utf8)
        conceptKey = card.conceptKey; originMemoryKey = card.originMemoryKey
        modality = card.modality; challenge = card.challenge
        self.qualityScore = qualityScore; isHidden = false; self.packID = packID
        lastPresentedAt = nil; presentationCount = 0
        updatedAt = Date()
    }
}

@Model
final class InteractionMetadataEntity {
    @Attribute(.unique) var interactionID: UUID
    var petID: String
    var memoryKey: String?
    var cardType: String?
    var contentSource: String?

    init(interactionID: UUID, petID: PetID, memoryKey: String? = nil, cardType: CardType? = nil, contentSource: String? = nil) {
        self.interactionID = interactionID
        self.petID = petID.rawValue
        self.memoryKey = memoryKey
        self.cardType = cardType?.rawValue
        self.contentSource = contentSource
    }
}

@Model
final class CardFeedbackEntity {
    @Attribute(.unique) var id: UUID
    var petID: String
    var memoryKey: String
    var contentFingerprint: String
    var feedbackType: String
    var createdAt: Date

    init(petID: PetID, memoryKey: String, fingerprint: String, feedback: CardFeedbackType) {
        id = UUID(); self.petID = petID.rawValue; self.memoryKey = memoryKey
        contentFingerprint = fingerprint; feedbackType = feedback.rawValue; createdAt = Date()
    }
}

@Model
final class PetContentPreferenceEntity {
    @Attribute(.unique) var petID: String
    var topicWeightsJSON: Data
    var mutedCardTypesJSON: Data
    var challengeBias: Int
    var updatedAt: Date

    init(petID: PetID) {
        self.petID = petID.rawValue; topicWeightsJSON = Data("{}".utf8)
        mutedCardTypesJSON = Data("[]".utf8); challengeBias = 0; updatedAt = Date()
    }
}

@Model
final class LearningEncounterEntity {
    @Attribute(.unique) var encounterKey: String
    var petID: String
    var conceptKey: String
    var firstSeenAt: Date
    var lastSeenAt: Date
    var presentationCount: Int
    var modalitiesJSON: Data
    var nextEligibleAt: Date

    init(card: GeneratedCard, now: Date = Date()) {
        let cardPetID = card.petID.rawValue
        let cardConceptKey = card.conceptKey
        petID = cardPetID; conceptKey = cardConceptKey
        encounterKey = "\(cardPetID)|\(cardConceptKey)"
        firstSeenAt = now; lastSeenAt = now; presentationCount = 1
        modalitiesJSON = (try? JSONEncoder().encode([card.modality])) ?? Data("[]".utf8)
        nextEligibleAt = now.addingTimeInterval(3 * 86_400)
    }
}

@Model
final class ChatMessageMetadataEntity {
    @Attribute(.unique) var messageID: UUID
    var correctionText: String?
    var deliveryState: String
    var updatedAt: Date

    init(messageID: UUID, state: ChatDeliveryState = .complete) {
        self.messageID = messageID; deliveryState = state.rawValue; updatedAt = Date()
    }
}

@Model
final class ContentPackEntity {
    @Attribute(.unique) var packID: String
    var title: String
    var version: String
    var author: String
    var language: String
    var license: String?
    var importedAt: Date
    var isEnabled: Bool

    init(id: String, title: String, version: String, author: String, language: String, license: String?) {
        packID = id; self.title = title; self.version = version; self.author = author
        self.language = language; self.license = license; importedAt = Date(); isEnabled = true
    }
}

@Model
final class ScheduleMetadataEntity {
    @Attribute(.unique) var scheduleID: UUID
    var originalText: String?
    var timeZoneID: String
    var nextFireAt: Date?

    init(scheduleID: UUID, originalText: String? = nil, timeZoneID: String = TimeZone.current.identifier) {
        self.scheduleID = scheduleID; self.originalText = originalText
        self.timeZoneID = timeZoneID
    }
}

@Model
final class ScheduleExecutionEntity {
    @Attribute(.unique) var id: UUID
    var scheduleID: UUID
    var petID: String
    var firedAt: Date
    var outcome: String
    var suppressionReason: String?

    init(scheduleID: UUID, petID: PetID, outcome: ScheduleExecutionOutcome, reason: String? = nil, at: Date = Date()) {
        id = UUID(); self.scheduleID = scheduleID; self.petID = petID.rawValue
        firedAt = at; self.outcome = outcome.rawValue; suppressionReason = reason
    }
}

// Keep the exact 0.1 model graph so SwiftData can identify and migrate an
// installed user's store. These types are migration-only; runtime code uses
// the top-level v2 model types above. Version identifiers remain computed so
// Xcode 16.4 does not treat a non-Sendable Schema.Version as shared state.
enum PolyPalsSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    @Model final class PetProfileEntity {
        @Attribute(.unique) var petID: String
        var name: String
        var targetLanguage: String
        var difficulty: String
        var languageRatio: Double
        var correctionMode: String
        var proactiveMode: String
        var quietStartHour: Int
        var quietEndHour: Int
        var isVisible: Bool
        var isSleeping: Bool
        var appearsOnAllSpaces: Bool
        var size: Double
        var relationshipPoints: Int
        var savesChatHistory: Bool
        var notificationEnabled: Bool
        var preferredVoiceIdentifier: String?
        var lastInteractionAt: Date?

        init() {
            petID = ""; name = ""; targetLanguage = ""; difficulty = ""
            languageRatio = 0; correctionMode = ""; proactiveMode = ""
            quietStartHour = 22; quietEndHour = 9; isVisible = true; isSleeping = false
            appearsOnAllSpaces = false; size = 128; relationshipPoints = 0
            savesChatHistory = true; notificationEnabled = false
        }
    }

    @Model final class PetMemoryEntity {
        @Attribute(.unique) var id: UUID
        var petID: String; var type: String; var content: String; var importance: Int
        var source: String; var createdAt: Date; var lastUsedAt: Date?; var userEditable: Bool
        init() { id = UUID(); petID = ""; type = ""; content = ""; importance = 0; source = ""; createdAt = Date(); userEditable = true }
    }

    @Model final class ChatThreadEntity {
        @Attribute(.unique) var id: UUID
        var petID: String; var title: String; var createdAt: Date; var updatedAt: Date
        init() { id = UUID(); petID = ""; title = ""; createdAt = Date(); updatedAt = Date() }
    }

    @Model final class ChatMessageEntity {
        @Attribute(.unique) var id: UUID
        var threadID: UUID; var petID: String; var role: String; var text: String
        var createdAt: Date; var isFavorite: Bool
        init() { id = UUID(); threadID = UUID(); petID = ""; role = ""; text = ""; createdAt = Date(); isFavorite = false }
    }

    @Model final class InventoryItemEntity {
        @Attribute(.unique) var id: UUID
        var petID: String; var kind: String; var title: String; var detail: String
        var createdAt: Date; var isFavorite: Bool
        init() { id = UUID(); petID = ""; kind = ""; title = ""; detail = ""; createdAt = Date(); isFavorite = false }
    }

    @Model final class ContentCardEntity {
        @Attribute(.unique) var id: UUID
        var petID: String; var type: String; var targetLanguage: String; var level: String
        var estimatedSeconds: Int; var encodedContent: Data; var source: String; var memoryKey: String
        var createdAt: Date; var isFavorite: Bool
        init() { id = UUID(); petID = ""; type = ""; targetLanguage = ""; level = ""; estimatedSeconds = 30; encodedContent = Data(); source = ""; memoryKey = ""; createdAt = Date(); isFavorite = false }
    }

    @Model final class InteractionEntity {
        @Attribute(.unique) var id: UUID
        var petID: String; var cardID: UUID?; var startedAt: Date; var endedAt: Date?
        var skipped: Bool; var responseType: String?; var userFeedback: String?
        init() { id = UUID(); petID = ""; startedAt = Date(); skipped = false }
    }

    @Model final class ScheduleEntity {
        @Attribute(.unique) var id: UUID
        var petID: String; var triggerType: String; var fireDate: Date?; var recurrence: String?
        var contentPreference: String; var isEnabled: Bool; var quietPolicy: String
        var usesSystemNotification: Bool; var isCoursePlan: Bool; var lastTriggeredAt: Date?; var createdAt: Date
        init() { id = UUID(); petID = ""; triggerType = ""; contentPreference = ""; isEnabled = true; quietPolicy = ""; usesSystemNotification = false; isCoursePlan = false; createdAt = Date() }
    }

    @Model final class PetWindowStateEntity {
        @Attribute(.unique) var petID: String
        var displayID: String?; var normalizedX: Double; var normalizedY: Double; var updatedAt: Date
        init() { petID = ""; normalizedX = 0; normalizedY = 0; updatedAt = Date() }
    }

    @Model final class LocalMetricEntity {
        @Attribute(.unique) var id: UUID
        var petID: String?; var day: Date; var name: String; var count: Int; var totalDuration: Double
        init() { id = UUID(); day = Date(); name = ""; count = 0; totalDuration = 0 }
    }

    static var models: [any PersistentModel.Type] {
        [
            PetProfileEntity.self, PetMemoryEntity.self, ChatThreadEntity.self,
            ChatMessageEntity.self, InventoryItemEntity.self, ContentCardEntity.self,
            InteractionEntity.self, ScheduleEntity.self, PetWindowStateEntity.self,
            LocalMetricEntity.self
        ]
    }
}

enum PolyPalsSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [
            PetProfileEntity.self, PetMemoryEntity.self, ChatThreadEntity.self,
            ChatMessageEntity.self, InventoryItemEntity.self, ContentCardEntity.self,
            InteractionEntity.self, RelationshipEventEntity.self, SchedulerStateEntity.self,
            ScheduleEntity.self, PetWindowStateEntity.self, LocalMetricEntity.self
        ]
    }
}

enum PolyPalsSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        PolyPalsSchemaV2.models + [
            PetProfileMetadataEntity.self,
            PetRoutineStateEntity.self, PetDailyStateEntity.self, InventoryEffectEntity.self,
            CardMetadataEntity.self, CardFeedbackEntity.self, PetContentPreferenceEntity.self,
            InteractionMetadataEntity.self, LearningEncounterEntity.self, ChatMessageMetadataEntity.self, ContentPackEntity.self,
            ScheduleMetadataEntity.self, ScheduleExecutionEntity.self
        ]
    }
}

enum PolyPalsSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }
    static var models: [any PersistentModel.Type] {
        PolyPalsSchemaV3.models + [LanguageProfileEntity.self]
    }
}

enum PolyPalsSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }
    static var models: [any PersistentModel.Type] {
        PolyPalsSchemaV4.models + [InventoryStoryEntity.self, PetQuietStateEntity.self]
    }
}

enum PolyPalsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PolyPalsSchemaV1.self, PolyPalsSchemaV2.self, PolyPalsSchemaV3.self, PolyPalsSchemaV4.self, PolyPalsSchemaV5.self] }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: PolyPalsSchemaV1.self, toVersion: PolyPalsSchemaV2.self),
            .lightweight(fromVersion: PolyPalsSchemaV2.self, toVersion: PolyPalsSchemaV3.self),
            .lightweight(fromVersion: PolyPalsSchemaV3.self, toVersion: PolyPalsSchemaV4.self),
            .lightweight(fromVersion: PolyPalsSchemaV4.self, toVersion: PolyPalsSchemaV5.self)
        ]
    }
}

enum PersistenceFactory {
    @MainActor
    private static func backfillV2Fields(in container: ModelContainer) throws {
        let context = container.mainContext
        let profiles = try context.fetch(FetchDescriptor<PetProfileEntity>())
        let profileMetadata = try context.fetch(FetchDescriptor<PetProfileMetadataEntity>())
        for profile in profiles {
            if let petID = PetID(rawValue: profile.petID) {
                if let metadata = profileMetadata.first(where: { $0.petID == profile.petID }) {
                    metadata.highestRelationshipLevelSeen = max(
                        metadata.highestRelationshipLevelSeen,
                        RelationshipLevel.forPoints(profile.relationshipPoints).number
                    )
                    metadata.updatedAt = Date()
                } else {
                    context.insert(PetProfileMetadataEntity(
                        petID: petID,
                        firstMetAt: profile.firstMetAt,
                        highestRelationshipLevelSeen: max(profile.highestRelationshipLevelSeen, RelationshipLevel.forPoints(profile.relationshipPoints).number)
                    ))
                }
            }
        }

        let languageProfiles = try context.fetch(FetchDescriptor<LanguageProfileEntity>())
        for profile in profiles {
            guard let petID = PetID(rawValue: profile.petID),
                  !languageProfiles.contains(where: { $0.petID == profile.petID }) else { continue }
            let definition = PetDefinition.definition(for: petID)
            let level = CEFRLevel.parse(profile.difficulty, default: definition.defaultLevel)
            let language = LanguageProfile(
                targetLanguage: profile.targetLanguage.isEmpty ? definition.targetLanguage : profile.targetLanguage,
                currentLevel: level,
                difficultyMode: .fixed,
                chineseHelpRatio: min(1, max(0, 1 - profile.languageRatio)),
                correctionMode: CorrectionMode(rawValue: profile.correctionMode) ?? .casual
            )
            context.insert(LanguageProfileEntity(petID: petID, profile: language))
            // Preserve the legacy field for old builds while normalizing Advanced.
            profile.difficulty = level.displayName
        }

        let cards = try context.fetch(FetchDescriptor<ContentCardEntity>())
        let cardMetadata = try context.fetch(FetchDescriptor<CardMetadataEntity>())
        for entity in cards {
            if let card = try? JSONDecoder().decode(GeneratedCard.self, from: entity.encodedContent) {
                if entity.contentFingerprint.isEmpty { entity.contentFingerprint = CardFingerprint.make(card) }
                let key = "\(card.petID.rawValue)|\(card.memoryKey)"
                if let metadata = cardMetadata.first(where: { $0.metadataKey == key }) {
                    if metadata.contentFingerprint.isEmpty { metadata.contentFingerprint = CardFingerprint.make(card) }
                } else {
                    context.insert(CardMetadataEntity(card: card, qualityScore: 100))
                }
            }
        }

        let cardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        let interactions = try context.fetch(FetchDescriptor<InteractionEntity>())
        let interactionMetadata = try context.fetch(FetchDescriptor<InteractionMetadataEntity>())
        for interaction in interactions {
            guard let cardID = interaction.cardID, let card = cardsByID[cardID] else { continue }
            guard let petID = PetID(rawValue: interaction.petID) else { continue }
            if let metadata = interactionMetadata.first(where: { $0.interactionID == interaction.id }) {
                if metadata.memoryKey == nil { metadata.memoryKey = card.memoryKey }
                if metadata.cardType == nil { metadata.cardType = card.type }
                if metadata.contentSource == nil { metadata.contentSource = card.source }
            } else {
                context.insert(InteractionMetadataEntity(
                    interactionID: interaction.id,
                    petID: petID,
                    memoryKey: card.memoryKey,
                    cardType: CardType(rawValue: card.type),
                    contentSource: card.source
                ))
            }
            if interaction.memoryKey == nil { interaction.memoryKey = card.memoryKey }
            if interaction.cardType == nil { interaction.cardType = card.type }
            if interaction.contentSource == nil { interaction.contentSource = card.source }
        }
        try context.save()
    }

    static func backupStoreBeforeMigration(fileManager: FileManager = .default) throws {
        guard UserDefaults.standard.integer(forKey: "dataSchemaVersion") < 5,
              let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let store = applicationSupport.appendingPathComponent("default.store")
        guard fileManager.fileExists(atPath: store.path) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupDirectory = applicationSupport
            .appendingPathComponent("PolyPals Backups", isDirectory: true)
            .appendingPathComponent("pre-v0.5-\(formatter.string(from: Date()))", isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: store.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.copyItem(at: source, to: backupDirectory.appendingPathComponent(source.lastPathComponent))
        }
    }

    @MainActor
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        if !inMemory { try backupStoreBeforeMigration() }
        let schema = Schema(versionedSchema: PolyPalsSchemaV5.self)
        let configuration = SwiftData.ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: PolyPalsMigrationPlan.self,
            configurations: configuration
        )
        if !inMemory { try backfillV2Fields(in: container) }
        if !inMemory { UserDefaults.standard.set(5, forKey: "dataSchemaVersion") }
        return container
    }

    @MainActor
    static func makeContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PolyPalsSchemaV5.self)
        let configuration = SwiftData.ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: PolyPalsMigrationPlan.self,
            configurations: configuration
        )
        try backfillV2Fields(in: container)
        return container
    }
}
