import CryptoKit
import Foundation
import SwiftData

enum CardFingerprint {
    static func make(_ card: GeneratedCard) -> String {
        let normalized = (card.targetText + "\n" + card.prompt)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation }
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct CardPresentationRecord: Sendable {
    let memoryKey: String
    let type: CardType
    let presentedAt: Date
}

struct CardSelectionPreferences: Sendable, Equatable {
    var topicWeights: [CardTopic: Int] = [:]
    var mutedTypes: Set<CardType> = []
    var challengeBias: Int = 0
    var hiddenConcepts: Set<String> = []
}

protocol CardRandomizing: AnyObject {
    func index(upperBound: Int) -> Int
}

final class SystemCardRandomizer: CardRandomizing {
    func index(upperBound: Int) -> Int { Int.random(in: 0..<max(1, upperBound)) }
}

final class SeededCardRandomizer: CardRandomizing {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    func index(upperBound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Int(state % UInt64(max(1, upperBound)))
    }
}

struct CardDeckService {
    let randomizer: any CardRandomizing

    init(randomizer: any CardRandomizing = SystemCardRandomizer()) {
        self.randomizer = randomizer
    }

    func select(
        from cards: [GeneratedCard],
        history: [CardPresentationRecord],
        energy: EnergyState,
        count: Int,
        preferences: CardSelectionPreferences = .init(),
        targetLevel: CEFRLevel? = nil
    ) -> [GeneratedCard] {
        let wanted = min(3, max(1, count))
        let recentKeys = Set(history.sorted { $0.presentedAt > $1.presentedAt }.prefix(10).map(\.memoryKey))
        let encounteredKeys = Set(history.map(\.memoryKey))
        let seenCounts = Dictionary(grouping: history, by: \.memoryKey).mapValues(\.count)
        let lastType = history.max(by: { $0.presentedAt < $1.presentedAt })?.type
        let preferred = preferredTypes(for: energy)
        var unique: [GeneratedCard] = []
        var keys = Set<String>()
        var fingerprints = Set<String>()
        for card in cards where !preferences.mutedTypes.contains(card.type) &&
                              !preferences.hiddenConcepts.contains(card.conceptKey) &&
                              !preferences.hiddenConcepts.contains(card.memoryKey) &&
                              keys.insert(card.memoryKey).inserted &&
                              fingerprints.insert(CardFingerprint.make(card)).inserted {
            unique.append(card)
        }

        var selected: [GeneratedCard] = []
        while selected.count < wanted && !unique.isEmpty {
            let recurrenceAlreadySelected = selected.contains { $0.originMemoryKey != nil }
            let recurrenceLimited = recurrenceAlreadySelected ? unique.filter { $0.originMemoryKey == nil } : unique
            let fresh = recurrenceLimited.filter { !recentKeys.contains($0.memoryKey) }
            let pool = fresh.isEmpty ? recurrenceLimited : fresh
            guard !pool.isEmpty else { break }
            let scored = pool.map { card -> (GeneratedCard, Int) in
                var score = seenCounts[card.memoryKey] == nil ? 100 : max(0, 30 - seenCounts[card.memoryKey, default: 0] * 3)
                if preferred.contains(card.type) { score += 20 }
                score += preferences.topicWeights[card.tags.first ?? .dailyLife, default: 0]
                if let origin = card.originMemoryKey, encounteredKeys.contains(origin), origin != card.memoryKey {
                    score += 18
                }
                if card.challenge == preferences.challengeBias { score += 15 }
                else if abs(card.challenge - preferences.challengeBias) > 1 { score -= 15 }
                if let targetLevel {
                    if card.recommendedLevel == targetLevel { score += 35 }
                    else if card.supports(targetLevel) { score += 15 }
                    else { score -= 100 }
                }
                if card.type == lastType || selected.last?.type == card.type { score -= 25 }
                return (card, score)
            }
            let bestScore = scored.map(\.1).max() ?? 0
            let best = scored.filter { $0.1 == bestScore }.map(\.0)
            let chosen = best[randomizer.index(upperBound: best.count)]
            selected.append(chosen)
            unique.removeAll { $0.memoryKey == chosen.memoryKey }
        }
        return selected
    }

    private func preferredTypes(for energy: EnergyState) -> Set<CardType> {
        switch energy {
        case .focused: [.expression, .listening, .dialogue]
        case .tired: [.listening, .picturePrompt, .expression]
        case .bored: [.scenario, .dialogue, .picturePrompt]
        case .curious: [.culture, .confusingWords, .expression]
        }
    }
}

@MainActor
struct CardRepository {
    let context: ModelContext

    func allCards(for petID: PetID) -> [GeneratedCard] {
        SeedContent.cards(for: petID) + cachedCards(for: petID)
    }

    func eligibleCards(for petID: PetID, at date: Date = Date(), calendar: Calendar = .current) -> [GeneratedCard] {
        let cards = allCards(for: petID)
        let encounters = ((try? context.fetch(FetchDescriptor<LearningEncounterEntity>())) ?? [])
            .filter { $0.petID == petID.rawValue }
        let week = calendar.dateInterval(of: .weekOfYear, for: date)
        let interactions = ((try? context.fetch(FetchDescriptor<InteractionEntity>())) ?? [])
            .filter { $0.petID == petID.rawValue && (week?.contains($0.startedAt) ?? false) }
        let metadata = (try? context.fetch(FetchDescriptor<CardMetadataEntity>())) ?? []
        return cards.filter { card in
            guard card.originMemoryKey != nil else { return true }
            guard let encounter = encounters.first(where: { $0.conceptKey == card.conceptKey }),
                  encounter.nextEligibleAt <= date else { return false }
            let modalities = (try? JSONDecoder().decode([String].self, from: encounter.modalitiesJSON)) ?? []
            guard modalities.last != card.modality else { return false }
            let weeklyRecurrences = interactions.filter { interaction in
                guard let key = interaction.memoryKey else { return false }
                return metadata.first(where: { $0.petID == petID.rawValue && $0.memoryKey == key })?.conceptKey == card.conceptKey && key != card.originMemoryKey
            }.count
            return weeklyRecurrences < 2
        }
    }

    func cachedCards(for petID: PetID) -> [GeneratedCard] {
        let enabledPackIDs = Set(((try? context.fetch(FetchDescriptor<ContentPackEntity>())) ?? [])
            .filter(\.isEnabled).map(\.packID))
        let metadata = (try? context.fetch(FetchDescriptor<CardMetadataEntity>())) ?? []
        let entities = ((try? context.fetch(FetchDescriptor<ContentCardEntity>())) ?? [])
            .filter { entity in
                guard entity.petID == petID.rawValue else { return false }
                guard entity.source == "pack" else { return true }
                let packID = metadata.first(where: {
                    $0.petID == entity.petID && $0.memoryKey == entity.memoryKey
                })?.packID
                return packID.map(enabledPackIDs.contains) ?? false
            }
        return entities.compactMap { try? JSONDecoder().decode(GeneratedCard.self, from: $0.encodedContent) }
    }

    func source(of card: GeneratedCard) -> String {
        let entities = (try? context.fetch(FetchDescriptor<ContentCardEntity>())) ?? []
        return entities.first(where: { $0.petID == card.petID.rawValue && $0.memoryKey == card.memoryKey })?.source ?? "seed"
    }

    func contentPacks() -> [ContentPackEntity] {
        ((try? context.fetch(FetchDescriptor<ContentPackEntity>())) ?? []).sorted { $0.title < $1.title }
    }

    func setContentPack(_ pack: ContentPackEntity, enabled: Bool) {
        pack.isEnabled = enabled
        try? context.save()
    }

    func deleteContentPack(_ pack: ContentPackEntity, keepFavorites: Bool = true) {
        let metadata = (try? context.fetch(FetchDescriptor<CardMetadataEntity>())) ?? []
        let keys = Set(metadata.filter { $0.packID == pack.packID }.map { "\($0.petID)|\($0.memoryKey)" })
        let cards = (try? context.fetch(FetchDescriptor<ContentCardEntity>())) ?? []
        for card in cards where keys.contains("\(card.petID)|\(card.memoryKey)") {
            let item = metadata.first(where: { $0.metadataKey == "\(card.petID)|\(card.memoryKey)" })
            if keepFavorites && card.isFavorite {
                card.source = "snapshot"
                item?.packID = nil
                item?.updatedAt = Date()
            } else {
                context.delete(card)
                if let item { context.delete(item) }
            }
        }
        context.delete(pack)
        try? context.save()
    }

    func selectionPreferences(for petID: PetID) -> CardSelectionPreferences {
        guard let entity = ((try? context.fetch(FetchDescriptor<PetContentPreferenceEntity>())) ?? [])
            .first(where: { $0.petID == petID.rawValue }) else { return .init() }
        let weights = (try? JSONDecoder().decode([CardTopic: Int].self, from: entity.topicWeightsJSON)) ?? [:]
        let muted = (try? JSONDecoder().decode(Set<CardType>.self, from: entity.mutedCardTypesJSON)) ?? []
        let feedback = ((try? context.fetch(FetchDescriptor<CardFeedbackEntity>())) ?? [])
            .filter { $0.petID == petID.rawValue && $0.feedbackType == CardFeedbackType.hideSimilar.rawValue }
        let metadata = (try? context.fetch(FetchDescriptor<CardMetadataEntity>())) ?? []
        let hiddenConcepts = Set(feedback.flatMap { item -> [String] in
            let concept = metadata.first(where: {
                $0.petID == item.petID && $0.memoryKey == item.memoryKey
            })?.conceptKey
            return [item.memoryKey, concept].compactMap { $0 }
        })
        return .init(topicWeights: weights, mutedTypes: muted, challengeBias: entity.challengeBias, hiddenConcepts: hiddenConcepts)
    }

    func ensurePreferences(for petID: PetID) -> PetContentPreferenceEntity {
        if let existing = ((try? context.fetch(FetchDescriptor<PetContentPreferenceEntity>())) ?? [])
            .first(where: { $0.petID == petID.rawValue }) { return existing }
        let created = PetContentPreferenceEntity(petID: petID)
        context.insert(created)
        return created
    }

    func recordFeedback(_ feedback: CardFeedbackType, for card: GeneratedCard) {
        let entity = CardFeedbackEntity(petID: card.petID, memoryKey: card.memoryKey, fingerprint: CardFingerprint.make(card), feedback: feedback)
        context.insert(entity)
        let prefs = ensurePreferences(for: card.petID)
        switch feedback {
        case .liked: break
        case .tooEasy: prefs.challengeBias = min(1, prefs.challengeBias + 1)
        case .tooHard: prefs.challengeBias = max(-1, prefs.challengeBias - 1)
        case .hideSimilar: break
        }
        var weights = (try? JSONDecoder().decode([CardTopic: Int].self, from: prefs.topicWeightsJSON)) ?? [:]
        for topic in card.tags {
            if feedback == .liked { weights[topic, default: 0] = min(40, weights[topic, default: 0] + 5) }
            if feedback == .hideSimilar { weights[topic, default: 0] = max(-40, weights[topic, default: 0] - 20) }
        }
        prefs.topicWeightsJSON = (try? JSONEncoder().encode(weights)) ?? Data("{}".utf8)
        try? context.save()
    }

    func undoFeedback(_ feedback: CardFeedbackType, for card: GeneratedCard) {
        let rows = ((try? context.fetch(FetchDescriptor<CardFeedbackEntity>())) ?? []).filter {
            $0.petID == card.petID.rawValue && $0.memoryKey == card.memoryKey && $0.feedbackType == feedback.rawValue
        }
        rows.forEach(context.delete)
        let prefs = ensurePreferences(for: card.petID)
        if feedback == .tooEasy { prefs.challengeBias = max(-1, prefs.challengeBias - 1) }
        if feedback == .tooHard { prefs.challengeBias = min(1, prefs.challengeBias + 1) }
        if feedback == .liked || feedback == .hideSimilar {
            var weights = (try? JSONDecoder().decode([CardTopic: Int].self, from: prefs.topicWeightsJSON)) ?? [:]
            for topic in card.tags {
                if feedback == .liked { weights[topic, default: 0] = max(-40, weights[topic, default: 0] - 5) }
                if feedback == .hideSimilar { weights[topic, default: 0] = min(40, weights[topic, default: 0] + 20) }
            }
            prefs.topicWeightsJSON = (try? JSONEncoder().encode(weights)) ?? Data("{}".utf8)
        }
        try? context.save()
    }

    func clearFeedback(for petID: PetID) {
        for row in ((try? context.fetch(FetchDescriptor<CardFeedbackEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) {
            context.delete(row)
        }
        let prefs = ensurePreferences(for: petID)
        prefs.topicWeightsJSON = Data("{}".utf8)
        prefs.mutedCardTypesJSON = Data("[]".utf8)
        prefs.challengeBias = 0
        try? context.save()
    }

    func markPresented(_ card: GeneratedCard, at date: Date = Date()) {
        let entities = (try? context.fetch(FetchDescriptor<ContentCardEntity>())) ?? []
        if let entity = entities.first(where: {
            $0.petID == card.petID.rawValue && $0.memoryKey == card.memoryKey
        }) {
            entity.presentationCount += 1
            entity.lastPresentedAt = date
        }
        let metadata = upsertMetadata(for: card)
        metadata.presentationCount += 1
        metadata.lastPresentedAt = date
    }

    func recordEncounter(_ card: GeneratedCard, at date: Date = Date()) {
        let key = "\(card.petID.rawValue)|\(card.conceptKey)"
        let encounters = (try? context.fetch(FetchDescriptor<LearningEncounterEntity>())) ?? []
        if let existing = encounters.first(where: { $0.encounterKey == key }) {
            existing.lastSeenAt = date
            existing.presentationCount += 1
            var modalities = (try? JSONDecoder().decode([String].self, from: existing.modalitiesJSON)) ?? []
            if !modalities.contains(card.modality) { modalities.append(card.modality) }
            existing.modalitiesJSON = (try? JSONEncoder().encode(modalities)) ?? existing.modalitiesJSON
            existing.nextEligibleAt = date.addingTimeInterval(modalities.count > 1 ? 7 * 86_400 : 3 * 86_400)
        } else {
            context.insert(LearningEncounterEntity(card: card, now: date))
        }
    }

    func history(for petID: PetID) -> [CardPresentationRecord] {
        let interactions = ((try? context.fetch(FetchDescriptor<InteractionEntity>())) ?? [])
            .filter { $0.petID == petID.rawValue }
        let metadata = (try? context.fetch(FetchDescriptor<InteractionMetadataEntity>())) ?? []
        return interactions.compactMap { entity in
            let details = metadata.first(where: { $0.interactionID == entity.id })
            guard let key = details?.memoryKey ?? entity.memoryKey,
                  let rawType = details?.cardType ?? entity.cardType,
                  let type = CardType(rawValue: rawType) else { return nil }
            return .init(memoryKey: key, type: type, presentedAt: entity.startedAt)
            }
    }

    @discardableResult
    func saveGenerated(_ card: GeneratedCard) -> Bool {
        let fingerprint = CardFingerprint.make(card)
        let existing = (try? context.fetch(FetchDescriptor<ContentCardEntity>())) ?? []
        let metadata = (try? context.fetch(FetchDescriptor<CardMetadataEntity>())) ?? []
        guard !existing.contains(where: {
            $0.petID == card.petID.rawValue && $0.memoryKey == card.memoryKey
        }) else { return false }
        guard !metadata.contains(where: {
            $0.petID == card.petID.rawValue && $0.contentFingerprint == fingerprint
        }) else { return false }
        let existingFingerprints = Set(existing.filter { $0.petID == card.petID.rawValue }.map { $0.contentFingerprint })
            .union(metadata.filter { $0.petID == card.petID.rawValue }.map { $0.contentFingerprint })
        let quality = CardQualityEvaluator().evaluate(card, pet: PetDefinition.definition(for: card.petID), existingFingerprints: existingFingerprints)
        guard quality.score >= 70 else { return false }
        guard let entity = try? ContentCardEntity(card: card, source: "ai") else { return false }
        context.insert(entity)
        upsertMetadata(for: card, qualityScore: quality.score)
        try? context.save()
        prune(for: card.petID)
        return true
    }

    @discardableResult
    func upsertMetadata(for card: GeneratedCard, packID: String? = nil, qualityScore: Int = 100) -> CardMetadataEntity {
        let key = "\(card.petID.rawValue)|\(card.memoryKey)"
        let metadata = ((try? context.fetch(FetchDescriptor<CardMetadataEntity>())) ?? [])
            .first(where: { $0.metadataKey == key })
        if let metadata {
            metadata.qualityScore = qualityScore
            if let packID { metadata.packID = packID }
            metadata.updatedAt = Date()
            return metadata
        } else {
            let created = CardMetadataEntity(card: card, packID: packID, qualityScore: qualityScore)
            context.insert(created)
            return created
        }
    }

    func prune(for petID: PetID, limit: Int = 100) {
        let entities = ((try? context.fetch(FetchDescriptor<ContentCardEntity>())) ?? [])
            .filter { $0.petID == petID.rawValue && $0.source == "ai" && !$0.isFavorite }
        let metadata = (try? context.fetch(FetchDescriptor<CardMetadataEntity>())) ?? []
        let ranked: [ContentCardEntity] = entities.sorted(by: { (lhs: ContentCardEntity, rhs: ContentCardEntity) -> Bool in
            let left = metadata.first(where: { $0.metadataKey == "\(lhs.petID)|\(lhs.memoryKey)" })
            let right = metadata.first(where: { $0.metadataKey == "\(rhs.petID)|\(rhs.memoryKey)" })
            let leftCount = left?.presentationCount ?? lhs.presentationCount
            let rightCount = right?.presentationCount ?? rhs.presentationCount
            if leftCount == rightCount {
                return (left?.lastPresentedAt ?? lhs.lastPresentedAt ?? lhs.createdAt) < (right?.lastPresentedAt ?? rhs.lastPresentedAt ?? rhs.createdAt)
            }
            return leftCount < rightCount
        })
        for entity in ranked.prefix(max(0, ranked.count - limit)) {
            context.delete(entity)
            let key = "\(entity.petID)|\(entity.memoryKey)"
            if let metadata = metadata.first(where: { $0.metadataKey == key }) { context.delete(metadata) }
        }
        try? context.save()
    }
}

struct ContentPackManifest: Codable, Sendable, Equatable {
    let id: String
    let title: String
    let version: String
    let author: String
    let language: String
    let license: String?
}

struct ContentPackDocument: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let pack: ContentPackManifest
    let cards: [GeneratedCard]
}

struct ContentPackPreview: Sendable, Equatable {
    let manifest: ContentPackManifest
    let cardCount: Int
    let typeCounts: [CardType: Int]
    let topics: [CardTopic]
    let conflictCount: Int
    let isUpgrade: Bool
}

enum ContentPackError: LocalizedError, Sendable {
    case tooLarge, unsupportedSchema, empty, invalidManifest, invalidCard(String), duplicate(String), conflict(String), cultureNeedsSource

    var errorDescription: String? {
        switch self {
        case .tooLarge: "内容包超过2MB。"
        case .unsupportedSchema: "内容包版本不受支持。"
        case .empty: "内容包没有卡片。"
        case .invalidManifest: "内容包清单不完整。"
        case let .invalidCard(key): "卡片无法通过验证：\(key)"
        case let .duplicate(key): "内容包中有重复卡片：\(key)"
        case let .conflict(key): "内容包与已有内容冲突：\(key)"
        case .cultureNeedsSource: "文化卡必须包含可核验来源。"
        }
    }
}

@MainActor
struct ContentPackImporter {
    let context: ModelContext

    func validate(_ data: Data) throws -> ContentPackDocument {
        guard data.count <= 2_000_000 else { throw ContentPackError.tooLarge }
        let document = try JSONDecoder().decode(ContentPackDocument.self, from: data)
        guard document.schemaVersion == 1 else { throw ContentPackError.unsupportedSchema }
        guard !document.pack.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !document.pack.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !document.pack.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !document.pack.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContentPackError.invalidManifest
        }
        guard !document.cards.isEmpty, document.cards.count <= 500 else { throw ContentPackError.empty }
        var keys = Set<String>()
        var fingerprints = Set<String>()
        for card in document.cards {
            guard card.isValid, card.estimatedSeconds >= 30, card.estimatedSeconds <= 120 else { throw ContentPackError.invalidCard(card.memoryKey) }
            guard keys.insert("\(card.petID.rawValue)|\(card.memoryKey)").inserted else { throw ContentPackError.duplicate(card.memoryKey) }
            guard fingerprints.insert(CardFingerprint.make(card)).inserted else { throw ContentPackError.duplicate(card.memoryKey) }
            if card.type == .culture && (card.sourceTitle?.isEmpty != false || card.sourceURL?.isEmpty != false) { throw ContentPackError.cultureNeedsSource }
            if let source = card.sourceURL, URL(string: source)?.scheme?.hasPrefix("http") != true { throw ContentPackError.invalidCard(card.memoryKey) }
        }
        return document
    }

    func preview(_ data: Data) throws -> ContentPackPreview {
        let document = try validate(data)
        let packs = (try? context.fetch(FetchDescriptor<ContentPackEntity>())) ?? []
        let cards = (try? context.fetch(FetchDescriptor<ContentCardEntity>())) ?? []
        let metadata = (try? context.fetch(FetchDescriptor<CardMetadataEntity>())) ?? []
        let ownKeys = Set(metadata.filter { $0.packID == document.pack.id }.map { "\($0.petID)|\($0.memoryKey)" })
        let conflicts = document.cards.filter { incoming in
            let key = "\(incoming.petID.rawValue)|\(incoming.memoryKey)"
            return cards.contains { "\($0.petID)|\($0.memoryKey)" == key } && !ownKeys.contains(key)
        }.count
        return .init(
            manifest: document.pack,
            cardCount: document.cards.count,
            typeCounts: Dictionary(grouping: document.cards, by: \.type).mapValues(\.count),
            topics: Array(Set(document.cards.flatMap(\.tags))).sorted { $0.rawValue < $1.rawValue },
            conflictCount: conflicts,
            isUpgrade: packs.contains { $0.packID == document.pack.id }
        )
    }

    func importPack(_ data: Data) throws -> ContentPackManifest {
        let document = try validate(data)
        let existing = ((try? context.fetch(FetchDescriptor<ContentPackEntity>())) ?? [])
        let existingCards = (try? context.fetch(FetchDescriptor<ContentCardEntity>())) ?? []
        let metadata = (try? context.fetch(FetchDescriptor<CardMetadataEntity>())) ?? []
        let ownKeys = Set(metadata.filter { $0.packID == document.pack.id }.map { "\($0.petID)|\($0.memoryKey)" })
        for card in document.cards {
            let key = "\(card.petID.rawValue)|\(card.memoryKey)"
            if existingCards.contains(where: { "\($0.petID)|\($0.memoryKey)" == key }) && !ownKeys.contains(key) {
                throw ContentPackError.conflict(card.memoryKey)
            }
        }
        // An upgrade replaces only cards owned by this pack. Validation and
        // collision checks complete before any mutation, preventing partial imports.
        for card in existingCards where ownKeys.contains("\(card.petID)|\(card.memoryKey)") && !card.isFavorite { context.delete(card) }
        for item in metadata where item.packID == document.pack.id { context.delete(item) }
        if let pack = existing.first(where: { $0.packID == document.pack.id }) {
            pack.version = document.pack.version
            pack.title = document.pack.title
            pack.author = document.pack.author
            pack.language = document.pack.language
            pack.license = document.pack.license
            pack.isEnabled = true
        } else {
            context.insert(ContentPackEntity(id: document.pack.id, title: document.pack.title, version: document.pack.version, author: document.pack.author, language: document.pack.language, license: document.pack.license))
        }
        for card in document.cards {
            let repository = CardRepository(context: context)
            let key = "\(card.petID.rawValue)|\(card.memoryKey)"
            if let preserved = existingCards.first(where: { "\($0.petID)|\($0.memoryKey)" == key && ownKeys.contains(key) && $0.isFavorite }) {
                preserved.source = "pack"
                repository.upsertMetadata(for: card, packID: document.pack.id, qualityScore: 100)
                continue
            }
            guard repository.savePackCard(card, packID: document.pack.id) else {
                context.rollback()
                throw ContentPackError.conflict(card.memoryKey)
            }
        }
        try context.save()
        return document.pack
    }
}

extension CardRepository {
    @discardableResult
    func savePackCard(_ card: GeneratedCard, packID: String) -> Bool {
        let existing = (try? context.fetch(FetchDescriptor<ContentCardEntity>())) ?? []
        guard !existing.contains(where: { $0.petID == card.petID.rawValue && $0.memoryKey == card.memoryKey }) else { return false }
        guard let entity = try? ContentCardEntity(card: card, source: "pack") else { return false }
        context.insert(entity)
        upsertMetadata(for: card, packID: packID, qualityScore: 100)
        return true
    }
}
