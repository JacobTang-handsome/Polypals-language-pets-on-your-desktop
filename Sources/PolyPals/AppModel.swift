import AppKit
import Foundation
import SwiftData
import PolyPalsPluginKit

struct ChatLine: Identifiable, Sendable, Equatable {
    let id: UUID
    let role: ChatRole
    var text: String
    let createdAt: Date
    var isFavorite: Bool

    init(id: UUID = UUID(), role: ChatRole, text: String, createdAt: Date = Date(), isFavorite: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.isFavorite = isFavorite
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let container: ModelContainer
    let focusTimer = FocusTimer()
    var scheduler: GlobalScheduler
    let keyStore = KeychainAPIKeyStore()
    private let modelClient: OpenAIResponsesClient
    private let cardDeck = CardDeckService()
    private var context: ModelContext { container.mainContext }

    @Published private(set) var profiles: [PetProfileEntity] = []
    @Published var selectedPet: PetID = .sol
    @Published var energyState: EnergyState = .focused
    @Published var presentationMode = false
    @Published var windowPerchingEnabled: Bool
    @Published private(set) var accessibilityTrusted: Bool
    @Published var todayOnlyPet: PetID?
    @Published var requestedTab: [PetID: Int] = [:]
    @Published var chatLines: [PetID: [ChatLine]] = [:]
    @Published var chatDrafts: [PetID: String] = [:]
    @Published var isChatting: Set<PetID> = []
    @Published var chatErrors: [PetID: String] = [:]
    @Published var cardPackages: [PetID: [GeneratedCard]] = [:]
    @Published var cardIndices: [PetID: Int] = [:]
    @Published var packageFinished: Set<PetID> = []
    @Published var memoryProposals: [PetID: [MemoryProposal]] = [:]
    @Published var isProposingMemory: Set<PetID> = []
    @Published var hasAPIKey = false
    @Published var modelID: String
    @Published var modelProvider: ModelProvider
    @Published var reasoningEffort: ReasoningEffort
    @Published var smartCardSupplement: Bool
    @Published var modelConnectionStatus: String?
    @Published var startupDataWarning: String?
    @Published var contentPackStatus: String?
    @Published var pendingContentPackPreview: ContentPackPreview?
    @Published var adaptiveLevelSuggestions: [PetID: CEFRLevel] = [:]
    @Published var installedPlugins: [InstalledPlugin] = []
    @Published var pendingPluginPreview: PluginValidationReport?
    private var pendingPluginURL: URL?
    private var pendingContentPackData: Data?
    @Published var schedulerSnapshot = SchedulerSnapshot()
    @Published var schedulerSuppressionReason: String?
    @Published var pendingInvitations: [PetID: InvitationCandidate] = [:]
    @Published var temporaryChatPets: Set<PetID> = []
    @Published var excludedContextMemoryIDs: [PetID: Set<UUID>] = [:]
    @Published var excludedContextItemIDs: [PetID: Set<UUID>] = [:]
    @Published private(set) var dailyStateRevision = UUID()
    private var lastFailedUserText: [PetID: String] = [:]
    private var chatTasks: [PetID: Task<Void, Never>] = [:]
    private var manuallyStoppedChats: Set<PetID> = []

    weak var windowManager: PetWindowManager?

    func openChatPanel(for petID: PetID) {
        windowManager?.openChat(petID)
    }

    private init() {
        do {
            container = try PersistenceFactory.makeContainer()
        } catch {
            container = try! PersistenceFactory.makeContainer(inMemory: true)
            startupDataWarning = "无法打开原数据，已使用临时安全会话。原数据与升级前备份未被删除：\(error.localizedDescription)"
        }
        let provider = ModelProvider(rawValue: UserDefaults.standard.string(forKey: "modelProvider") ?? "") ?? .openAI
        let configuredModel = UserDefaults.standard.string(forKey: "modelID") ?? provider.defaultModel
        let effort = ReasoningEffort(rawValue: UserDefaults.standard.string(forKey: "reasoningEffort") ?? "") ?? .none
        let globalLimit = min(6, max(0, UserDefaults.standard.object(forKey: "globalDailyInvitationLimit") as? Int ?? 2))
        scheduler = GlobalScheduler(limits: SchedulerLimits(globalDailyLimit: globalLimit, perPetDailyLimit: 1, minimumInterval: 90 * 60))
        modelProvider = provider
        modelID = configuredModel
        reasoningEffort = effort
        smartCardSupplement = UserDefaults.standard.object(forKey: "smartCardSupplement") as? Bool ?? true
        windowPerchingEnabled = UserDefaults.standard.object(forKey: "windowPerchingEnabled") as? Bool ?? false
        accessibilityTrusted = AccessibilityPermission.isTrusted
        modelClient = OpenAIResponsesClient(
            keyStore: keyStore,
            configuration: .init(provider: provider, modelID: configuredModel, reasoningEffort: effort)
        )
        bootstrap()
        hasAPIKey = (try? keyStore.loadAPIKey(for: provider))?.isEmpty == false
        restoreSchedulerState()
        schedulerSnapshot.focusSessionActive = focusTimer.isRunning
        focusTimer.onCompletion = { [weak self] in self?.focusCompleted() }
    }

    func bootstrap() {
        let descriptor = FetchDescriptor<PetProfileEntity>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let known = Set(existing.map(\.petID))
        for definition in PetDefinition.builtIns where !known.contains(definition.id.rawValue) {
            context.insert(PetProfileEntity(definition: definition))
        }
        try? context.save()
        reloadProfiles()
        for pet in PetID.allCases { loadChat(for: pet) }
        performMaintenance()
        reloadInstalledPlugins()
    }

    func reloadProfiles() {
        profiles = ((try? context.fetch(FetchDescriptor<PetProfileEntity>())) ?? [])
            .sorted { $0.petID < $1.petID }
    }

    private func schedulerState() -> SchedulerStateEntity {
        if let state = ((try? context.fetch(FetchDescriptor<SchedulerStateEntity>())) ?? []).first { return state }
        let state = SchedulerStateEntity()
        context.insert(state)
        try? context.save()
        return state
    }

    private func restoreSchedulerState() {
        let state = schedulerState()
        let today = Calendar.current.startOfDay(for: Date())
        guard Calendar.current.isDate(state.day, inSameDayAs: today) else {
            resetDailySchedulerState(now: Date())
            return
        }
        schedulerSnapshot.lastGlobalInvitationAt = state.lastGlobalInvitationAt
        schedulerSnapshot.globalInvitationCountToday = state.globalInvitationCountToday
        schedulerSnapshot.petInvitationCountToday = (try? JSONDecoder().decode([PetID: Int].self, from: state.petCountsJSON)) ?? [:]
        schedulerSnapshot.rejectedPetsToday = (try? JSONDecoder().decode(Set<PetID>.self, from: state.rejectedPetsJSON)) ?? []
        schedulerSnapshot.consecutiveDeclines = state.consecutiveDeclines
        schedulerSnapshot.quietUntil = state.quietUntil
        if let day = UserDefaults.standard.object(forKey: "todayOnlyPetDay") as? Date,
           Calendar.current.isDate(day, inSameDayAs: today),
           let raw = UserDefaults.standard.string(forKey: "todayOnlyPet"),
           let pet = PetID(rawValue: raw) {
            todayOnlyPet = pet
            schedulerSnapshot.todayOnlyPet = pet
        }
    }

    func persistSchedulerState() {
        let state = schedulerState()
        state.day = Calendar.current.startOfDay(for: Date())
        state.lastGlobalInvitationAt = schedulerSnapshot.lastGlobalInvitationAt
        state.globalInvitationCountToday = schedulerSnapshot.globalInvitationCountToday
        state.petCountsJSON = (try? JSONEncoder().encode(schedulerSnapshot.petInvitationCountToday)) ?? Data("{}".utf8)
        state.rejectedPetsJSON = (try? JSONEncoder().encode(schedulerSnapshot.rejectedPetsToday)) ?? Data("[]".utf8)
        state.consecutiveDeclines = schedulerSnapshot.consecutiveDeclines
        state.quietUntil = schedulerSnapshot.quietUntil
        try? context.save()
    }

    func resetDailySchedulerState(now: Date) {
        schedulerSnapshot.globalInvitationCountToday = 0
        schedulerSnapshot.petInvitationCountToday = [:]
        schedulerSnapshot.rejectedPetsToday = []
        schedulerSnapshot.consecutiveDeclines = 0
        schedulerSnapshot.quietUntil = nil
        todayOnlyPet = nil
        schedulerSnapshot.todayOnlyPet = nil
        UserDefaults.standard.removeObject(forKey: "todayOnlyPet")
        UserDefaults.standard.removeObject(forKey: "todayOnlyPetDay")
        let state = schedulerState()
        state.day = Calendar.current.startOfDay(for: now)
        persistSchedulerState()
    }

    func profile(for petID: PetID) -> PetProfileEntity {
        if let profile = profiles.first(where: { $0.petID == petID.rawValue }) { return profile }
        let profile = PetProfileEntity(definition: PetDefinition.definition(for: petID))
        context.insert(profile)
        try? context.save()
        reloadProfiles()
        return profile
    }

    func profileMetadata(for petID: PetID) -> PetProfileMetadataEntity {
        if let metadata = ((try? context.fetch(FetchDescriptor<PetProfileMetadataEntity>())) ?? [])
            .first(where: { $0.petID == petID.rawValue }) { return metadata }
        let existing = profile(for: petID)
        let metadata = PetProfileMetadataEntity(
            petID: petID,
            firstMetAt: existing.firstMetAt,
            highestRelationshipLevelSeen: max(existing.highestRelationshipLevelSeen, RelationshipLevel.forPoints(existing.relationshipPoints).number)
        )
        context.insert(metadata)
        try? context.save()
        return metadata
    }

    func languageProfile(for petID: PetID) -> LanguageProfile {
        if let stored = ((try? context.fetch(FetchDescriptor<LanguageProfileEntity>())) ?? [])
            .first(where: { $0.petID == petID.rawValue }) { return stored.value }
        let legacy = profile(for: petID)
        let definition = PetDefinition.definition(for: petID)
        let value = LanguageProfile(
            targetLanguage: legacy.targetLanguage.isEmpty ? definition.targetLanguage : legacy.targetLanguage,
            currentLevel: CEFRLevel.parse(legacy.difficulty, default: definition.defaultLevel),
            chineseHelpRatio: min(1, max(0, 1 - legacy.languageRatio)),
            correctionMode: CorrectionMode(rawValue: legacy.correctionMode) ?? .casual
        )
        context.insert(LanguageProfileEntity(petID: petID, profile: value))
        try? context.save()
        return value
    }

    func updateLanguageProfile(_ value: LanguageProfile, for petID: PetID) {
        let stored = ((try? context.fetch(FetchDescriptor<LanguageProfileEntity>())) ?? [])
            .first(where: { $0.petID == petID.rawValue })
        if let stored { stored.update(from: value) }
        else { context.insert(LanguageProfileEntity(petID: petID, profile: value)) }
        let legacy = profile(for: petID)
        legacy.targetLanguage = value.targetLanguage
        legacy.difficulty = value.currentLevel.displayName
        legacy.languageRatio = 1 - value.chineseHelpRatio
        legacy.correctionMode = value.correctionMode.rawValue
        try? context.save()
        reloadProfiles()
        objectWillChange.send()
    }

    func acceptAdaptiveLevelSuggestion(for petID: PetID) {
        guard let level = adaptiveLevelSuggestions.removeValue(forKey: petID) else { return }
        var value = languageProfile(for: petID)
        value.currentLevel = level
        value.receptiveLevel = level
        value.productiveLevel = level
        updateLanguageProfile(value, for: petID)
    }

    func dismissAdaptiveLevelSuggestion(for petID: PetID) {
        adaptiveLevelSuggestions[petID] = nil
    }

    func firstMetAt(for petID: PetID) -> Date { profileMetadata(for: petID).firstMetAt }

    func relationshipGreeting(for petID: PetID) -> String {
        let name = PetDefinition.definition(for: petID).name
        switch relationshipLevel(for: petID).number {
        case 1: return "嗨，我是 \(name)。先认识一下。"
        case 2: return "又见面了，\(name) 记得你。"
        case 3: return "\(name) 已经知道你喜欢从哪里开始了。"
        case 4: return "朋友，今天想从哪件小事开始？"
        case 5: return "好朋友，\(name) 给你留了一个熟悉的小角落。"
        case 6: return "默契伙伴上线。我们继续刚才那点想法。"
        default: return "老朋友，\(name) 把共同经历带来了。"
        }
    }

    func setTodayOnlyPet(_ petID: PetID?) {
        todayOnlyPet = petID
        schedulerSnapshot.todayOnlyPet = petID
        if let petID {
            UserDefaults.standard.set(petID.rawValue, forKey: "todayOnlyPet")
            UserDefaults.standard.set(Calendar.current.startOfDay(for: Date()), forKey: "todayOnlyPetDay")
        } else {
            UserDefaults.standard.removeObject(forKey: "todayOnlyPet")
            UserDefaults.standard.removeObject(forKey: "todayOnlyPetDay")
        }
    }

    func markInteraction(with petID: PetID) {
        selectedPet = petID
        let profile = profile(for: petID)
        profile.lastInteractionAt = Date()
        recordMetric("interaction", petID: petID)
        try? context.save()
        reloadProfiles()
    }

    func routineState(for petID: PetID) -> PetRoutineStateEntity {
        if let state = ((try? context.fetch(FetchDescriptor<PetRoutineStateEntity>())) ?? [])
            .first(where: { $0.petID == petID.rawValue }) { return state }
        let state = PetRoutineStateEntity(petID: petID)
        context.insert(state)
        try? context.save()
        return state
    }

    func dailyState(for petID: PetID, now: Date = Date()) -> PetDailyStateEntity {
        let start = Calendar.current.startOfDay(for: now)
        if let state = ((try? context.fetch(FetchDescriptor<PetDailyStateEntity>())) ?? [])
            .first(where: { $0.petID == petID.rawValue && Calendar.current.isDate($0.day, inSameDayAs: start) }) { return state }
        let state = PetDailyStateEntity(petID: petID, day: now)
        context.insert(state)
        return state
    }

    func recordAmbientAction(_ action: AmbientAction, for petID: PetID, at date: Date = Date()) {
        let routine = routineState(for: petID)
        var recent = (try? JSONDecoder().decode([AmbientAction].self, from: routine.recentActionsJSON)) ?? []
        recent.insert(action, at: 0)
        routine.recentActionsJSON = (try? JSONEncoder().encode(Array(recent.prefix(3)))) ?? Data("[]".utf8)
        routine.lastAmbientAction = action.rawValue
        routine.lastAmbientActionAt = date
        if action == .nap { routine.lastNapAt = date }
        if action == .tidyItem { routine.lastTidyAt = date }
        routine.updatedAt = date
        let daily = dailyState(for: petID, now: date)
        switch action {
        case .nap: daily.napCount += 1
        case .stretch: daily.stretchCount += 1
        case .tidyItem: daily.tidyCount += 1
        case .walkToEdge: daily.walkCount += 1
        default: break
        }
        if daily.noteworthyMomentKey == nil { daily.noteworthyMomentKey = action.rawValue }
        daily.updatedAt = date
        dailyStateRevision = UUID()
        try? context.save()
    }

    func ambientInventoryItem(for petID: PetID, at date: Date = Date()) -> InventoryItemEntity? {
        let effects = (try? context.fetch(FetchDescriptor<InventoryEffectEntity>())) ?? []
        return inventory(for: petID)
            .filter { item in
                guard let last = effects.first(where: { $0.inventoryItemID == item.id })?.lastReferencedAt else { return true }
                return date.timeIntervalSince(last) >= 24 * 60 * 60
            }
            .sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
                let left = effects.first(where: { $0.inventoryItemID == lhs.id })?.referenceCount ?? 0
                let right = effects.first(where: { $0.inventoryItemID == rhs.id })?.referenceCount ?? 0
                if left != right { return left < right }
                return lhs.createdAt < rhs.createdAt
            }
            .first
    }

    func recordAmbientInventoryReference(_ item: InventoryItemEntity, at date: Date = Date()) {
        let effects = (try? context.fetch(FetchDescriptor<InventoryEffectEntity>())) ?? []
        let effect = effects.first(where: { $0.inventoryItemID == item.id }) ?? {
            let created = InventoryEffectEntity(itemID: item.id, petID: PetID(rawValue: item.petID) ?? .sol)
            context.insert(created)
            return created
        }()
        effect.referenceCount += 1
        effect.lastReferencedAt = date
        try? context.save()
    }

    func todaySummary(for petID: PetID, now: Date = Date()) -> String {
        let state = dailyState(for: petID, now: now)
        let name = PetDefinition.definition(for: petID).name
        var parts: [String] = []
        if state.walkCount > 0 { parts.append("在屏幕边缘散步了\(state.walkCount)次") }
        if state.napCount > 0 { parts.append("打盹了\(state.napCount)次") }
        if state.tidyCount > 0 { parts.append("整理了\(state.tidyCount)件小物品") }
        if state.completedCardCount > 0 { parts.append("和你看过\(state.completedCardCount)张卡片") }
        if parts.isEmpty { return "今天，\(name)还在安静地陪着你。" }
        return "今天，\(name)\(parts.joined(separator: "，"))."
    }

    func recordCardFeedback(_ feedback: CardFeedbackType, for card: GeneratedCard) {
        let today = Calendar.current.startOfDay(for: Date())
        let alreadyRecorded = ((try? context.fetch(FetchDescriptor<CardFeedbackEntity>())) ?? []).contains {
            $0.petID == card.petID.rawValue && $0.memoryKey == card.memoryKey &&
            $0.feedbackType == feedback.rawValue && $0.createdAt >= today
        }
        guard !alreadyRecorded else { return }
        CardRepository(context: context).recordFeedback(feedback, for: card)
        refreshAdaptiveSuggestion(for: card.petID)
        if feedback == .liked { awardRelationship(.favorite, to: card.petID) }
        objectWillChange.send()
    }

    func undoCardFeedback(_ feedback: CardFeedbackType, for card: GeneratedCard) {
        CardRepository(context: context).undoFeedback(feedback, for: card)
        objectWillChange.send()
    }

    func clearCardFeedback(for petID: PetID) {
        CardRepository(context: context).clearFeedback(for: petID)
        adaptiveLevelSuggestions[petID] = nil
        objectWillChange.send()
    }

    private func refreshAdaptiveSuggestion(for petID: PetID) {
        let profile = languageProfile(for: petID)
        guard profile.difficultyMode == .adaptive else { adaptiveLevelSuggestions[petID] = nil; return }
        let recent = ((try? context.fetch(FetchDescriptor<CardFeedbackEntity>())) ?? [])
            .filter { $0.petID == petID.rawValue && ($0.feedbackType == CardFeedbackType.tooEasy.rawValue || $0.feedbackType == CardFeedbackType.tooHard.rawValue) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(3)
        guard recent.count == 3, Set(recent.map(\.feedbackType)).count == 1 else { return }
        if recent.first?.feedbackType == CardFeedbackType.tooEasy.rawValue, profile.currentLevel != .c2 {
            adaptiveLevelSuggestions[petID] = profile.currentLevel.higher
        } else if recent.first?.feedbackType == CardFeedbackType.tooHard.rawValue, profile.currentLevel != .a1 {
            adaptiveLevelSuggestions[petID] = profile.currentLevel.lower
        }
    }

    @discardableResult
    func awardRelationship(_ event: RelationshipEvent, to petID: PetID, now: Date = Date()) -> Int {
        let day = Calendar.current.startOfDay(for: now)
        let events = ((try? context.fetch(FetchDescriptor<RelationshipEventEntity>())) ?? [])
            .filter { $0.petID == petID.rawValue && $0.day == day }
        let sameEventCount = events.filter { $0.eventType == event.rawValue && $0.pointsAwarded > 0 }.count
        let awardedToday = events.reduce(0) { $0 + $1.pointsAwarded }
        let points = RelationshipAwardPolicy.points(for: event, sameEventCount: sameEventCount, pointsAwardedToday: awardedToday)
        guard points > 0 else { return 0 }
        let profile = profile(for: petID)
        let oldLevel = RelationshipLevel.forPoints(profile.relationshipPoints)
        profile.relationshipPoints += points
        let newLevel = RelationshipLevel.forPoints(profile.relationshipPoints)
        let profileMetadata = profileMetadata(for: petID)
        profileMetadata.highestRelationshipLevelSeen = max(profileMetadata.highestRelationshipLevelSeen, newLevel.number)
        profileMetadata.updatedAt = now
        profile.highestRelationshipLevelSeen = max(profile.highestRelationshipLevelSeen, newLevel.number)
        context.insert(RelationshipEventEntity(petID: petID, event: event, pointsAwarded: points, now: now))
        try? context.save()
        reloadProfiles()
        if newLevel.number > oldLevel.number { windowManager?.playRelationshipLevelUp(petID) }
        return points
    }

    func relationshipLevel(for petID: PetID) -> RelationshipLevel {
        RelationshipLevel.forPoints(profile(for: petID).relationshipPoints)
    }

    func relationshipProgress(for petID: PetID) -> Double {
        let profile = profile(for: petID)
        return relationshipLevel(for: petID).progress(points: profile.relationshipPoints)
    }

    func setModelID(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelID = trimmed
        UserDefaults.standard.set(trimmed, forKey: "modelID")
        updateModelClient()
    }

    func saveAPIKey(_ key: String) throws {
        try keyStore.saveAPIKey(key, for: modelProvider)
        hasAPIKey = !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func deleteAPIKey() throws {
        try keyStore.deleteAPIKey(for: modelProvider)
        hasAPIKey = false
    }

    func setModelProvider(_ provider: ModelProvider) {
        modelProvider = provider
        modelID = provider.defaultModel
        reasoningEffort = .none
        UserDefaults.standard.set(provider.rawValue, forKey: "modelProvider")
        UserDefaults.standard.set(modelID, forKey: "modelID")
        UserDefaults.standard.set(reasoningEffort.rawValue, forKey: "reasoningEffort")
        hasAPIKey = (try? keyStore.loadAPIKey(for: provider))?.isEmpty == false
        modelConnectionStatus = nil
        updateModelClient()
    }

    func setReasoningEffort(_ effort: ReasoningEffort) {
        reasoningEffort = effort
        UserDefaults.standard.set(effort.rawValue, forKey: "reasoningEffort")
        updateModelClient()
    }

    func setSmartCardSupplement(_ enabled: Bool) {
        smartCardSupplement = enabled
        UserDefaults.standard.set(enabled, forKey: "smartCardSupplement")
    }

    var globalDailyInvitationLimit: Int { scheduler.limits.globalDailyLimit }

    func setGlobalDailyInvitationLimit(_ value: Int) {
        let clamped = min(6, max(0, value))
        scheduler.limits.globalDailyLimit = clamped
        UserDefaults.standard.set(clamped, forKey: "globalDailyInvitationLimit")
        schedulerSnapshot.globalInvitationCountToday = min(schedulerSnapshot.globalInvitationCountToday, clamped)
        persistSchedulerState()
        objectWillChange.send()
    }

    func startFocus(minutes: Int) {
        schedulerSnapshot.focusSessionActive = true
        focusTimer.start(minutes: minutes)
        objectWillChange.send()
    }

    func stopFocus() {
        focusTimer.stop()
        schedulerSnapshot.focusSessionActive = false
        objectWillChange.send()
    }

    func importContentPack(_ data: Data) {
        do {
            let manifest = try ContentPackImporter(context: context).importPack(data)
            contentPackStatus = "已导入：\(manifest.title)"
        } catch {
            contentPackStatus = error.localizedDescription
        }
    }

    func previewContentPack(_ data: Data) {
        do {
            let preview = try ContentPackImporter(context: context).preview(data)
            pendingContentPackData = data
            pendingContentPackPreview = preview
            contentPackStatus = nil
        } catch {
            pendingContentPackData = nil
            pendingContentPackPreview = nil
            contentPackStatus = error.localizedDescription
        }
    }

    func confirmContentPackImport() {
        guard let data = pendingContentPackData else { return }
        pendingContentPackData = nil
        pendingContentPackPreview = nil
        importContentPack(data)
    }

    func cancelContentPackImport() {
        pendingContentPackData = nil
        pendingContentPackPreview = nil
    }

    func reloadInstalledPlugins() {
        installedPlugins = (try? PluginPackService().installed()) ?? []
    }

    func previewPluginPack(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            cancelPluginPreview()
            let previewURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("polypals-preview-\(UUID().uuidString).polypals-pack", isDirectory: true)
            try FileManager.default.copyItem(at: url, to: previewURL)
            let report = try PluginPackService().preview(previewURL)
            pendingPluginURL = previewURL
            pendingPluginPreview = report
            contentPackStatus = report.isValid ? nil : report.issues.map(\.message).joined(separator: "\n")
        } catch { contentPackStatus = error.localizedDescription }
    }

    func confirmPluginInstall() {
        guard let url = pendingPluginURL else { return }
        do {
            let service = try PluginPackService()
            let installed = try service.install(url)
            if let data = try service.contentDocumentData(for: installed) { importContentPack(data) }
            contentPackStatus = "已安装并验证：\(installed.manifest.name)"
            reloadInstalledPlugins()
        } catch { contentPackStatus = error.localizedDescription }
        cancelPluginPreview(clearStatus: false)
    }

    func cancelPluginPreview(clearStatus: Bool = true) {
        if let url = pendingPluginURL { try? FileManager.default.removeItem(at: url) }
        pendingPluginURL = nil
        pendingPluginPreview = nil
        if clearStatus { contentPackStatus = nil }
    }

    func setPlugin(_ plugin: InstalledPlugin, enabled: Bool) {
        do {
            try PluginPackService().setEnabled(enabled, id: plugin.id)
            if plugin.manifest.kind == .content,
               let pack = contentPacks().first(where: { $0.packID == plugin.id }) { setContentPack(pack, enabled: enabled) }
            reloadInstalledPlugins()
        } catch { contentPackStatus = error.localizedDescription }
    }

    func deletePlugin(_ plugin: InstalledPlugin) {
        do {
            if let pack = contentPacks().first(where: { $0.packID == plugin.id }) { deleteContentPack(pack) }
            try PluginPackService().delete(plugin)
            contentPackStatus = "已删除插件；收藏内容已保留快照。"
            reloadInstalledPlugins()
        } catch { contentPackStatus = error.localizedDescription }
    }

    func contentPacks() -> [ContentPackEntity] { CardRepository(context: context).contentPacks() }

    func setContentPack(_ pack: ContentPackEntity, enabled: Bool) {
        CardRepository(context: context).setContentPack(pack, enabled: enabled)
        objectWillChange.send()
    }

    func deleteContentPack(_ pack: ContentPackEntity, keepFavorites: Bool = true) {
        CardRepository(context: context).deleteContentPack(pack, keepFavorites: keepFavorites)
        contentPackStatus = "已删除内容包“\(pack.title)”。"
        objectWillChange.send()
    }

    func testModelConnection() {
        modelConnectionStatus = "正在测试连接…"
        Task {
            do {
                let status = try await modelClient.testConnection()
                modelConnectionStatus = "已连接 \(status.provider.title) · \(status.modelID)"
            } catch {
                let category = ModelFailureCategory.classify(error)
                modelConnectionStatus = "\(category.title)：\(error.localizedDescription)"
            }
        }
    }

    private func updateModelClient() {
        let configuration = ModelConfiguration(provider: modelProvider, modelID: modelID, reasoningEffort: reasoningEffort)
        Task { await modelClient.setConfiguration(configuration) }
    }

    func loadChat(for petID: PetID) {
        let stored = ((try? context.fetch(FetchDescriptor<ChatMessageEntity>())) ?? [])
            .filter { $0.petID == petID.rawValue }
            .sorted { $0.createdAt < $1.createdAt }
            .suffix(100)
        chatLines[petID] = stored.compactMap { entity in
            guard let role = ChatRole(rawValue: entity.role) else { return nil }
            return ChatLine(id: entity.id, role: role, text: entity.text, createdAt: entity.createdAt, isFavorite: entity.isFavorite)
        }
    }

    func correctionText(for messageID: UUID) -> String? {
        ((try? context.fetch(FetchDescriptor<ChatMessageMetadataEntity>())) ?? [])
            .first(where: { $0.messageID == messageID })?.correctionText
    }

    func sendChat(to petID: PetID) {
        let draft = chatDrafts[petID, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty, !isChatting.contains(petID) else { return }
        guard draft.count <= 8_000 else {
            chatErrors[petID] = "单次消息最多 8,000 个字符，请缩短后再发送。"
            return
        }
        chatDrafts[petID] = ""
        chatLines[petID, default: []].append(ChatLine(role: .user, text: draft))
        persistMessageIfEnabled(petID: petID, role: .user, text: draft)
        markInteraction(with: petID)
        beginChat(to: petID, userText: draft)
    }

    private func beginChat(to petID: PetID, userText: String) {
        guard !isChatting.contains(petID) else { return }
        chatErrors[petID] = nil
        lastFailedUserText[petID] = nil
        isChatting.insert(petID)
        windowManager?.play(.processing, for: petID)

        let definition = PetDefinition.definition(for: petID)
        let profile = profile(for: petID)
        let snapshot = makeChatContextSnapshot(for: petID, excludingLastLine: true)
        // Context exclusions are intentionally one-request-only. The immutable
        // snapshot above remains the source of truth for the in-flight request.
        excludedContextMemoryIDs[petID] = []
        excludedContextItemIDs[petID] = []
        let request = ChatRequest(
            pet: definition,
            correctionMode: snapshot.correctionMode,
            energy: snapshot.energy,
            userText: userText,
            confirmedMemories: snapshot.confirmedMemories,
            recentMessages: snapshot.recentMessages,
            relationshipLevel: snapshot.relationshipLevel,
            relationshipTitle: snapshot.relationshipTitle,
            inventoryItems: snapshot.inventoryItems,
            languageProfile: languageProfile(for: petID)
        )
        let assistantID = UUID()
        chatLines[petID, default: []].append(ChatLine(id: assistantID, role: .assistant, text: ""))

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await modelClient.streamChat(request)
                for try await event in stream {
                    if case let .textDelta(delta) = event,
                       let index = chatLines[petID]?.firstIndex(where: { $0.id == assistantID }) {
                        chatLines[petID]?[index].text += delta
                    }
                }
                if let rawText = chatLines[petID]?.first(where: { $0.id == assistantID })?.text, !rawText.isEmpty {
                    let segments = ChatResponseSegments(rawText: rawText)
                    if let index = chatLines[petID]?.firstIndex(where: { $0.id == assistantID }) {
                        chatLines[petID]?[index].text = segments.answer
                    }
                    persistMessageIfEnabled(petID: petID, role: .assistant, text: segments.answer, id: assistantID)
                    if profile.savesChatHistory && !temporaryChatPets.contains(petID) {
                        upsertChatMetadata(messageID: assistantID, state: .complete, correction: segments.correction)
                    }
                    recordInventoryReferences(for: petID, in: segments.answer)
                    awardRelationship(.chat, to: petID)
                    let daily = dailyState(for: petID)
                    daily.chatCount += 1
                    daily.updatedAt = Date()
                    dailyStateRevision = UUID()
                    try? context.save()
                    windowManager?.play(.waving, for: petID)
                }
            } catch {
                let userCancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                if userCancelled, self.manuallyStoppedChats.remove(petID) != nil {
                    if let text = chatLines[petID]?.first(where: { $0.id == assistantID })?.text, !text.isEmpty {
                        persistMessageIfEnabled(petID: petID, role: .assistant, text: text, id: assistantID)
                        if profile.savesChatHistory && !temporaryChatPets.contains(petID) {
                            upsertChatMetadata(messageID: assistantID, state: .cancelled)
                        }
                    }
                    chatErrors[petID] = "已停止生成；已有内容已保留。"
                } else {
                // A broken SSE response is not kept as if it were a complete answer.
                // The user's message remains visible and can be retried explicitly.
                chatLines[petID]?.removeAll(where: { $0.id == assistantID })
                lastFailedUserText[petID] = userText
                let category = ModelFailureCategory.classify(error)
                chatErrors[petID] = "\(category.title)：\(error.localizedDescription)"
                windowManager?.play(.failed, for: petID)
                }
            }
            self.manuallyStoppedChats.remove(petID)
            isChatting.remove(petID)
            chatTasks[petID] = nil
        }
        chatTasks[petID] = task
    }

    func stopChat(for petID: PetID) {
        guard isChatting.contains(petID) else { return }
        manuallyStoppedChats.insert(petID)
        chatTasks[petID]?.cancel()
        isChatting.remove(petID)
        windowManager?.play(.idle, for: petID)
    }

    func setTemporaryChat(_ enabled: Bool, for petID: PetID) {
        if enabled { temporaryChatPets.insert(petID) } else { temporaryChatPets.remove(petID) }
    }

    @discardableResult
    func editLastUserMessage(for petID: PetID) -> String? {
        guard !isChatting.contains(petID), let lines = chatLines[petID],
              let index = lines.lastIndex(where: { $0.role == .user }) else { return nil }
        let text = lines[index].text
        let removed = Array(lines[index...])
        chatLines[petID]?.removeSubrange(index...)
        let removedIDs = Set(removed.map { $0.id })
        let stored = ((try? context.fetch(FetchDescriptor<ChatMessageEntity>())) ?? [])
            .filter { removedIDs.contains($0.id) }
        stored.forEach(context.delete)
        let metadata = ((try? context.fetch(FetchDescriptor<ChatMessageMetadataEntity>())) ?? [])
            .filter { removedIDs.contains($0.messageID) }
        metadata.forEach(context.delete)
        try? context.save()
        chatDrafts[petID] = text
        return text
    }

    func startPackage(for petID: PetID, count: Int = 2, temporaryLevel: CEFRLevel? = nil) {
        let bounded = min(3, max(1, count))
        let repository = CardRepository(context: context)
        var effectiveLanguage = languageProfile(for: petID)
        if let temporaryLevel { effectiveLanguage.currentLevel = temporaryLevel }
        cardPackages[petID] = cardDeck.select(
            from: repository.eligibleCards(for: petID),
            history: repository.history(for: petID),
            energy: energyState,
            count: bounded,
            preferences: repository.selectionPreferences(for: petID),
            targetLevel: effectiveLanguage.currentLevel
        )
        cardIndices[petID] = 0
        packageFinished.remove(petID)
        markInteraction(with: petID)
        if hasAPIKey && smartCardSupplement { supplementPackageWithAI(for: petID, languageProfile: effectiveLanguage) }
    }

    func currentCard(for petID: PetID) -> GeneratedCard? {
        let cards = cardPackages[petID, default: []]
        let index = cardIndices[petID, default: 0]
        return cards.indices.contains(index) ? cards[index] : nil
    }

    func cardSource(_ card: GeneratedCard) -> String {
        CardRepository(context: context).source(of: card)
    }

    func advanceCard(for petID: PetID, skipped: Bool = false) {
        guard let card = currentCard(for: petID) else { return }
        let repository = CardRepository(context: context)
        let source = repository.source(of: card)
        repository.markPresented(card)
        repository.recordEncounter(card)
        let interaction = InteractionEntity(petID: petID, cardID: card.id, memoryKey: card.memoryKey, cardType: card.type, contentSource: source)
        interaction.endedAt = Date()
        interaction.skipped = skipped
        context.insert(interaction)
        context.insert(InteractionMetadataEntity(
            interactionID: interaction.id,
            petID: petID,
            memoryKey: card.memoryKey,
            cardType: card.type,
            contentSource: source
        ))
        if !skipped {
            awardRelationship(.cardCompleted, to: petID)
            let daily = dailyState(for: petID)
            daily.completedCardCount += 1
            daily.updatedAt = Date()
            dailyStateRevision = UUID()
            windowManager?.celebrate(petID)
        }
        let next = cardIndices[petID, default: 0] + 1
        if next >= cardPackages[petID, default: []].count {
            packageFinished.insert(petID)
        } else {
            cardIndices[petID] = next
        }
        recordMetric(skipped ? "card_skipped" : "card_completed", petID: petID)
        try? context.save()
        reloadProfiles()
    }

    func replaceCurrentCardWithAI(for petID: PetID) {
        guard hasAPIKey, let current = currentCard(for: petID), current.type != .culture else { return }
        Task {
            do {
                let card = try await modelClient.generateCard(
                    for: PetDefinition.definition(for: petID),
                    languageProfile: languageProfile(for: petID),
                    type: current.type,
                    energy: energyState
                )
                _ = CardRepository(context: context).saveGenerated(card)
                let index = cardIndices[petID, default: 0]
                if cardPackages[petID]?.indices.contains(index) == true { cardPackages[petID]?[index] = card }
            } catch {
                chatErrors[petID] = "已保留审核卡片：\(error.localizedDescription)"
            }
        }
    }

    private func supplementPackageWithAI(for petID: PetID, languageProfile: LanguageProfile) {
        guard let package = cardPackages[petID], !package.isEmpty else { return }
        let replaceIndex = max(0, package.count - 1)
        let fallbackTypes = package.map(\.type).filter { $0 != .culture }
        guard let type = fallbackTypes.last ?? CardType.allCases.filter({ $0 != .culture }).randomElement() else { return }
        Task {
            do {
                let card = try await modelClient.generateCard(
                    for: PetDefinition.definition(for: petID), languageProfile: languageProfile, type: type, energy: energyState
                )
                let repository = CardRepository(context: context)
                guard repository.saveGenerated(card) else { return }
                if cardPackages[petID]?.indices.contains(replaceIndex) == true,
                   cardIndices[petID, default: 0] < replaceIndex {
                    cardPackages[petID]?[replaceIndex] = card
                }
            } catch {
                // Online supplementation is optional; the reviewed offline package remains intact.
            }
        }
    }

    func favoriteCurrentCard(for petID: PetID) {
        guard let card = currentCard(for: petID) else { return }
        guard !inventory(for: petID).contains(where: { $0.kind == "card" && $0.title == card.targetText }) else { return }
        context.insert(InventoryItemEntity(petID: petID, kind: "card", title: card.targetText, detail: card.chineseHelp, isFavorite: true))
        let cached = (try? context.fetch(FetchDescriptor<ContentCardEntity>())) ?? []
        cached.first(where: { $0.petID == petID.rawValue && $0.memoryKey == card.memoryKey })?.isFavorite = true
        awardRelationship(.favorite, to: petID)
        recordMetric("favorite", petID: petID)
        try? context.save()
        reloadProfiles()
    }

    func giveGift(to petID: PetID, title: String = "一块小饼干") {
        let item = InventoryItemEntity(petID: petID, kind: "gift", title: title, detail: "你送给 \(PetDefinition.definition(for: petID).name) 的小礼物。")
        context.insert(item)
        context.insert(InventoryEffectEntity(itemID: item.id, petID: petID, tags: ["gift", "dailyLife"]))
        awardRelationship(.gift, to: petID)
        let daily = dailyState(for: petID)
        daily.giftCount += 1
        daily.updatedAt = Date()
        dailyStateRevision = UUID()
        recordMetric("gift", petID: petID)
        try? context.save()
        reloadProfiles()
    }

    func inventory(for petID: PetID) -> [InventoryItemEntity] {
        ((try? context.fetch(FetchDescriptor<InventoryItemEntity>())) ?? [])
            .filter { $0.petID == petID.rawValue }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func weeklyEncounteredWords(for petID: PetID, now: Date = Date()) -> [String] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: now)) ?? now
        let encounters = ((try? context.fetch(FetchDescriptor<LearningEncounterEntity>())) ?? [])
            .filter { $0.petID == petID.rawValue && $0.lastSeenAt >= start }
            .sorted { $0.lastSeenAt > $1.lastSeenAt }
        let cards = CardRepository(context: context).allCards(for: petID)
        var seen = Set<String>()
        return encounters.compactMap { encounter in
            let text = cards.first(where: { $0.conceptKey == encounter.conceptKey })?.targetText ?? encounter.conceptKey
            return seen.insert(text).inserted ? text : nil
        }.prefix(8).map { $0 }
    }

    func deleteInventoryItem(_ item: InventoryItemEntity) {
        context.delete(item)
        try? context.save()
    }

    func makeReviewCard(from line: ChatLine, petID: PetID) {
        guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let title = String(line.text.prefix(180))
        guard !inventory(for: petID).contains(where: { $0.kind == "review-card" && $0.title == title }) else { return }
        context.insert(InventoryItemEntity(
            petID: petID, kind: "review-card", title: title,
            detail: "从与 \(PetDefinition.definition(for: petID).name) 的聊天制作，可在背包中再次查看。", isFavorite: true
        ))
        awardRelationship(.favorite, to: petID)
        try? context.save()
    }

    func memories(for petID: PetID) -> [PetMemoryEntity] {
        ((try? context.fetch(FetchDescriptor<PetMemoryEntity>())) ?? [])
            .filter { $0.petID == petID.rawValue }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func requestMemoryProposals(for petID: PetID) {
        let transcript = String(chatLines[petID, default: []].suffix(20)
            .map { "\($0.role.rawValue): \(String($0.text.prefix(1_500)))" }
            .joined(separator: "\n")
            .prefix(12_000))
        guard !transcript.isEmpty, hasAPIKey else { return }
        isProposingMemory.insert(petID)
        Task {
            do {
                memoryProposals[petID] = try await modelClient.proposeMemories(
                    for: PetDefinition.definition(for: petID),
                    transcript: transcript
                )
            } catch {
                let category = ModelFailureCategory.classify(error)
                chatErrors[petID] = "\(category.title)：\(error.localizedDescription)"
            }
            isProposingMemory.remove(petID)
        }
    }

    func confirmMemory(_ proposal: MemoryProposal, petID: PetID) {
        context.insert(PetMemoryEntity(petID: petID, type: proposal.type, content: proposal.content, importance: proposal.importance))
        memoryProposals[petID]?.removeAll(where: { $0.id == proposal.id })
        awardRelationship(.memoryConfirmed, to: petID)
        try? context.save()
    }

    func updateMemoryProposal(_ proposalID: UUID, petID: PetID, content: String) {
        guard let index = memoryProposals[petID]?.firstIndex(where: { $0.id == proposalID }) else { return }
        memoryProposals[petID]?[index].content = content
    }

    func deleteMemory(_ memory: PetMemoryEntity) {
        context.delete(memory)
        try? context.save()
    }

    func updateMemory(_ memory: PetMemoryEntity, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        memory.content = trimmed
        try? context.save()
    }

    func clearMemories(for petID: PetID) {
        for memory in memories(for: petID) { context.delete(memory) }
        try? context.save()
    }

    func favoriteChatLine(_ line: ChatLine, petID: PetID, title: String? = nil, translation: String? = nil, tags: [String] = []) {
        guard !line.text.isEmpty else { return }
        let item = InventoryItemEntity(
            petID: petID,
            kind: "chat",
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title! : line.text,
            detail: translation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? translation! : "收藏自与 \(PetDefinition.definition(for: petID).name) 的聊天",
            isFavorite: true
        )
        context.insert(item)
        context.insert(InventoryEffectEntity(itemID: item.id, petID: petID, tags: tags))
        awardRelationship(.favorite, to: petID)
        if let message = ((try? context.fetch(FetchDescriptor<ChatMessageEntity>())) ?? [])
            .first(where: { $0.id == line.id && $0.petID == petID.rawValue }) {
            message.isFavorite = true
        }
        if let index = chatLines[petID]?.firstIndex(where: { $0.id == line.id }) {
            chatLines[petID]?[index].isFavorite = true
        }
        recordMetric("chat_favorite", petID: petID)
        try? context.save()
        reloadProfiles()
    }

    func retryLastChat(for petID: PetID) {
        guard !isChatting.contains(petID),
              let text = lastFailedUserText[petID] ?? chatLines[petID]?.last(where: { $0.role == .user })?.text else { return }
        beginChat(to: petID, userText: text)
    }

    func discardEphemeralChat(for petID: PetID) {
        guard temporaryChatPets.contains(petID) || !profile(for: petID).savesChatHistory else { return }
        chatLines[petID] = []
        chatDrafts[petID] = ""
        chatErrors[petID] = nil
        memoryProposals[petID] = []
        temporaryChatPets.remove(petID)
    }

    func schedules(for petID: PetID) -> [ScheduleEntity] {
        ((try? context.fetch(FetchDescriptor<ScheduleEntity>())) ?? [])
            .filter { $0.petID == petID.rawValue }
            .sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }
    }

    func isPetQuiet(_ petID: PetID, at date: Date) -> Bool {
        let profile = profile(for: petID)
        return scheduler.isQuietHour(
            date,
            calendar: .current,
            start: profile.quietStartHour,
            end: profile.quietEndHour
        )
    }

    func addSchedule(
        for petID: PetID,
        at date: Date,
        recurrence: String,
        content: String,
        usesSystemNotification: Bool = false,
        isCoursePlan: Bool = false,
        originalText: String? = nil
    ) {
        let normalizedRecurrence: String? = ["daily", "weekly"].contains(recurrence) ? recurrence : nil
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }
        let schedule = ScheduleEntity(
            petID: petID,
            trigger: .calendar,
            fireDate: date,
            recurrence: normalizedRecurrence,
            contentPreference: trimmedContent,
            usesSystemNotification: usesSystemNotification,
            isCoursePlan: isCoursePlan
        )
        context.insert(schedule)
        if originalText != nil { context.insert(ScheduleMetadataEntity(scheduleID: schedule.id, originalText: originalText)) }
        try? context.save()
        if usesSystemNotification {
            Task {
                let result = (try? await NotificationService.shared.schedule(
                    schedule,
                    pet: PetDefinition.definition(for: petID)
                )) ?? .failed
                if !result.usesSystemNotification {
                    schedule.usesSystemNotification = false
                    self.recordScheduleExecution(
                        scheduleID: schedule.id,
                        petID: petID,
                        outcome: result == .permissionDenied ? .notificationDenied : .suppressed,
                        reason: result == .suppressedConflict ? "通知时间冲突，已降级为桌宠动作" : "系统通知不可用，已降级为桌宠动作"
                    )
                    try? context.save()
                }
            }
        }
    }

    func addParsedSchedule(
        _ draft: ParsedScheduleDraft,
        fallbackPetID: PetID,
        usesSystemNotification: Bool,
        isCoursePlan: Bool,
        originalText: String
    ) {
        guard draft.confidence >= 0.75 else { return }
        let petID = draft.petID ?? fallbackPetID
        let content = draft.contentPreference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        if draft.trigger == .focusCompletion {
            let schedule = ScheduleEntity(
                petID: petID,
                trigger: .focusCompletion,
                fireDate: nil,
                recurrence: nil,
                contentPreference: content,
                usesSystemNotification: false,
                isCoursePlan: isCoursePlan
            )
            context.insert(schedule)
            context.insert(ScheduleMetadataEntity(scheduleID: schedule.id, originalText: originalText))
            try? context.save()
            return
        }
        guard let fireDate = draft.fireDate else { return }
        addSchedule(
            for: petID,
            at: fireDate,
            recurrence: draft.recurrence ?? "once",
            content: content,
            usesSystemNotification: usesSystemNotification,
            isCoursePlan: isCoursePlan,
            originalText: originalText
        )
    }

    func addDailySchedule(for petID: PetID, at date: Date, content: String) {
        addSchedule(for: petID, at: date, recurrence: "daily", content: content)
    }

    func recordScheduleExecution(_ candidate: InvitationCandidate, outcome: ScheduleExecutionOutcome, reason: String? = nil, at date: Date = Date()) {
        guard let scheduleID = candidate.sourceScheduleID else { return }
        recordScheduleExecution(scheduleID: scheduleID, petID: candidate.petID, outcome: outcome, reason: reason, at: date)
    }

    func recordScheduleExecution(scheduleID: UUID, petID: PetID, outcome: ScheduleExecutionOutcome, reason: String? = nil, at date: Date = Date()) {
        context.insert(ScheduleExecutionEntity(scheduleID: scheduleID, petID: petID, outcome: outcome, reason: reason, at: date))
        try? context.save()
    }

    func scheduleHistory(for petID: PetID) -> [ScheduleExecutionEntity] {
        ((try? context.fetch(FetchDescriptor<ScheduleExecutionEntity>())) ?? [])
            .filter { $0.petID == petID.rawValue }
            .sorted { $0.firedAt > $1.firedAt }
            .prefix(30).map { $0 }
    }

    func consumeDueRuntimeSchedules(now: Date, deliveryWindow: TimeInterval = 75) -> [InvitationCandidate] {
        let calendar = Calendar.current
        let schedules = ((try? context.fetch(FetchDescriptor<ScheduleEntity>())) ?? [])
            .filter { $0.isEnabled && !$0.usesSystemNotification && $0.triggerType == ScheduleTrigger.calendar.rawValue }
        var candidates: [InvitationCandidate] = []

        for schedule in schedules {
            guard let petID = PetID(rawValue: schedule.petID),
                  let fireDate = schedule.fireDate,
                  let occurrence = ScheduleOccurrenceResolver.mostRecent(
                    fireDate: fireDate,
                    recurrence: schedule.recurrence,
                    now: now,
                    calendar: calendar
                  ),
                  schedule.lastTriggeredAt == nil || schedule.lastTriggeredAt! < occurrence else { continue }

            // Mark every occurrence consumed before deciding. Quiet/conflicting/expired
            // events are deliberately not backfilled on a later timer tick.
            schedule.lastTriggeredAt = occurrence
            guard now.timeIntervalSince(occurrence) <= deliveryWindow else { continue }
            candidates.append(InvitationCandidate(
                petID: petID,
                priority: schedule.isCoursePlan ? .courseSchedule : .ordinarySchedule,
                createdAt: occurrence,
                expiresAt: occurrence.addingTimeInterval(deliveryWindow),
                title: "\(PetDefinition.definition(for: petID).name) 的计划到了",
                body: schedule.contentPreference,
                sourceScheduleID: schedule.id
            ))
        }
        try? context.save()
        return candidates
    }

    func deleteSchedule(_ schedule: ScheduleEntity) {
        if let pet = PetID(rawValue: schedule.petID) { NotificationService.shared.cancel(petID: pet, scheduleID: schedule.id) }
        context.delete(schedule)
        try? context.save()
    }

    func setScheduleEnabled(_ schedule: ScheduleEntity, enabled: Bool) {
        schedule.isEnabled = enabled
        try? context.save()
        guard let petID = PetID(rawValue: schedule.petID) else { return }
        if !enabled {
            NotificationService.shared.cancel(petID: petID, scheduleID: schedule.id)
        } else if schedule.usesSystemNotification {
            Task {
                let result = (try? await NotificationService.shared.schedule(
                    schedule,
                    pet: PetDefinition.definition(for: petID)
                )) ?? .failed
                if !result.usesSystemNotification {
                    schedule.usesSystemNotification = false
                    self.recordScheduleExecution(
                        scheduleID: schedule.id,
                        petID: petID,
                        outcome: result == .permissionDenied ? .notificationDenied : .suppressed,
                        reason: result == .suppressedConflict ? "通知时间冲突，已降级为桌宠动作" : "系统通知不可用，已降级为桌宠动作"
                    )
                    try? context.save()
                }
            }
        }
    }

    func disableSchedule(petID: PetID, scheduleID: UUID) {
        guard let schedule = schedules(for: petID).first(where: { $0.id == scheduleID }) else { return }
        setScheduleEnabled(schedule, enabled: false)
    }

    func resetPet(_ petID: PetID) async {
        let petSchedules = schedules(for: petID)
        let petMessages = ((try? context.fetch(FetchDescriptor<ChatMessageEntity>())) ?? []).filter { $0.petID == petID.rawValue }
        let petItems = inventory(for: petID)
        for message in petMessages { context.delete(message) }
        for thread in ((try? context.fetch(FetchDescriptor<ChatThreadEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) { context.delete(thread) }
        for memory in memories(for: petID) { context.delete(memory) }
        for item in petItems { context.delete(item) }
        for schedule in petSchedules { context.delete(schedule) }
        for card in ((try? context.fetch(FetchDescriptor<ContentCardEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) { context.delete(card) }
        for interaction in ((try? context.fetch(FetchDescriptor<InteractionEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) { context.delete(interaction) }
        for event in ((try? context.fetch(FetchDescriptor<RelationshipEventEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) { context.delete(event) }
        for metric in ((try? context.fetch(FetchDescriptor<LocalMetricEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) { context.delete(metric) }
        for state in ((try? context.fetch(FetchDescriptor<PetWindowStateEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) { context.delete(state) }
        for state in ((try? context.fetch(FetchDescriptor<PetRoutineStateEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) { context.delete(state) }
        for state in ((try? context.fetch(FetchDescriptor<PetDailyStateEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) { context.delete(state) }
        for metadata in ((try? context.fetch(FetchDescriptor<PetProfileMetadataEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) { context.delete(metadata) }
        for preference in ((try? context.fetch(FetchDescriptor<PetContentPreferenceEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) { context.delete(preference) }
        for metadata in ((try? context.fetch(FetchDescriptor<CardMetadataEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) { context.delete(metadata) }
        for feedback in ((try? context.fetch(FetchDescriptor<CardFeedbackEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) { context.delete(feedback) }
        for encounter in ((try? context.fetch(FetchDescriptor<LearningEncounterEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) { context.delete(encounter) }
        for metadata in ((try? context.fetch(FetchDescriptor<InteractionMetadataEntity>())) ?? []).filter({ $0.petID == petID.rawValue }) { context.delete(metadata) }
        let petItemIDs = Set(petItems.map { $0.id })
        for effect in ((try? context.fetch(FetchDescriptor<InventoryEffectEntity>())) ?? []).filter({ petItemIDs.contains($0.inventoryItemID) }) { context.delete(effect) }
        let petMessageIDs = Set(petMessages.map { $0.id })
        for metadata in ((try? context.fetch(FetchDescriptor<ChatMessageMetadataEntity>())) ?? []).filter({ petMessageIDs.contains($0.messageID) }) { context.delete(metadata) }
        let scheduleIDs = Set(petSchedules.map { $0.id })
        for metadata in ((try? context.fetch(FetchDescriptor<ScheduleMetadataEntity>())) ?? []).filter({ scheduleIDs.contains($0.scheduleID) }) { context.delete(metadata) }
        for execution in ((try? context.fetch(FetchDescriptor<ScheduleExecutionEntity>())) ?? []).filter({ scheduleIDs.contains($0.scheduleID) }) { context.delete(execution) }
        if let oldProfile = profiles.first(where: { $0.petID == petID.rawValue }) { context.delete(oldProfile) }
        context.insert(PetProfileEntity(definition: PetDefinition.definition(for: petID)))
        try? context.save()
        await NotificationService.shared.cancelAll(for: petID)
        chatLines[petID] = []
        cardPackages[petID] = []
        memoryProposals[petID] = []
        reloadProfiles()
        windowManager?.refresh(petID)
    }

    func windowState(for petID: PetID) -> PetWindowStateEntity? {
        ((try? context.fetch(FetchDescriptor<PetWindowStateEntity>())) ?? [])
            .first(where: { $0.petID == petID.rawValue })
    }

    func saveWindowState(petID: PetID, displayID: String?, normalizedX: Double, normalizedY: Double) {
        if let state = windowState(for: petID) {
            state.displayID = displayID
            state.normalizedX = normalizedX
            state.normalizedY = normalizedY
            state.updatedAt = Date()
        } else {
            context.insert(PetWindowStateEntity(
                petID: petID,
                displayID: displayID,
                normalizedX: normalizedX,
                normalizedY: normalizedY
            ))
        }
        try? context.save()
    }

    func recordMetric(_ name: String, petID: PetID? = nil, duration: TimeInterval = 0) {
        context.insert(LocalMetricEntity(petID: petID, day: Date(), name: name, totalDuration: duration))
        try? context.save()
    }

    func exportMetrics() -> String {
        let metrics = (try? context.fetch(FetchDescriptor<LocalMetricEntity>())) ?? []
        let header = "day,pet,event,count,duration"
        let formatter = ISO8601DateFormatter()
        let rows = metrics.map {
            "\(formatter.string(from: $0.day)),\($0.petID ?? "global"),\($0.name),\($0.count),\($0.totalDuration)"
        }
        return ([header] + rows).joined(separator: "\n")
    }

    func clearMetrics() {
        let metrics = (try? context.fetch(FetchDescriptor<LocalMetricEntity>())) ?? []
        for metric in metrics { context.delete(metric) }
        try? context.save()
    }

    func performMaintenance(now: Date = Date()) {
        do {
            let calendar = Calendar.current
            let dailyCutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
            for state in try context.fetch(FetchDescriptor<PetDailyStateEntity>()) where state.day < dailyCutoff {
                context.delete(state)
            }
            let historyCutoff = calendar.date(byAdding: .day, value: -90, to: now) ?? .distantPast
            let executions = try context.fetch(FetchDescriptor<ScheduleExecutionEntity>())
            for petID in PetID.allCases {
                let rows = executions.filter { $0.petID == petID.rawValue }.sorted { $0.firedAt > $1.firedAt }
                for row in rows.enumerated() where row.offset >= 500 || row.element.firedAt < historyCutoff {
                    context.delete(row.element)
                }
                CardRepository(context: context).prune(for: petID)
            }
            let messageIDs = Set(try context.fetch(FetchDescriptor<ChatMessageEntity>()).map(\.id))
            for metadata in try context.fetch(FetchDescriptor<ChatMessageMetadataEntity>()) where !messageIDs.contains(metadata.messageID) {
                context.delete(metadata)
            }
            try context.save()
        } catch {
            // Best effort only: maintenance must never prevent launch.
        }
    }

    func contextPreview(for petID: PetID) -> String {
        let snapshot = makeChatContextSnapshot(for: petID)
        let confirmed = snapshot.confirmedMemories.map { "• \($0)" }
        let items = snapshot.inventoryItems.map { "• \($0)" }
        return "当前消息 · 最近聊天 \(snapshot.recentMessages.count) 条 · 已确认记忆 \(confirmed.count) 条 · 背包物品 \(items.count) 件\n" +
            (confirmed.isEmpty ? "已确认记忆：无" : "已确认记忆：\n" + confirmed.joined(separator: "\n")) + "\n" +
            (items.isEmpty ? "背包物品：无" : "背包物品：\n" + items.joined(separator: "\n"))
    }

    func makeChatContextSnapshot(for petID: PetID, excludingLastLine: Bool = false) -> ChatContextSnapshot {
        let profile = profile(for: petID)
        let level = relationshipLevel(for: petID)
        let policy = RelationshipExpressionPolicy.policy(for: level.number)
        let selectedMemories = memories(for: petID)
            .filter { !excludedContextMemoryIDs[petID, default: []].contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.importance != rhs.importance { return lhs.importance > rhs.importance }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(policy.maximumMemoryReferences)
            .map(\.content)
        let selectedItems = inventory(for: petID)
            .filter { !excludedContextItemIDs[petID, default: []].contains($0.id) }
            .filter { item in
                let effects = (try? context.fetch(FetchDescriptor<InventoryEffectEntity>())) ?? []
                guard let last = effects.first(where: { $0.inventoryItemID == item.id })?.lastReferencedAt else { return true }
                return Date().timeIntervalSince(last) >= 24 * 60 * 60
            }
            .prefix(2)
            .map { "\($0.title)：\($0.detail)" }
        let lines = excludingLastLine ? chatLines[petID, default: []].dropLast() : chatLines[petID, default: []][...]
        return ChatContextSnapshot(
            petID: petID,
            correctionMode: CorrectionMode(rawValue: profile.correctionMode) ?? .casual,
            energy: energyState,
            relationshipLevel: level.number,
            relationshipTitle: level.title,
            confirmedMemories: Array(selectedMemories),
            inventoryItems: Array(selectedItems),
            recentMessages: lines.suffix(16).map { ($0.role, $0.text) }
        )
    }

    func setMemoryIncludedInNextRequest(_ memoryID: UUID, petID: PetID, included: Bool) {
        if included { excludedContextMemoryIDs[petID, default: []].remove(memoryID) }
        else { excludedContextMemoryIDs[petID, default: []].insert(memoryID) }
    }

    func setItemIncludedInNextRequest(_ itemID: UUID, petID: PetID, included: Bool) {
        if included { excludedContextItemIDs[petID, default: []].remove(itemID) }
        else { excludedContextItemIDs[petID, default: []].insert(itemID) }
    }

    func togglePresentationMode() {
        presentationMode.toggle()
        schedulerSnapshot.presentationMode = presentationMode
        windowManager?.setPetsHidden(presentationMode)
        Task { await NotificationService.shared.setPresentationMode(presentationMode) }
    }

    func setWindowPerchingEnabled(_ enabled: Bool) {
        windowPerchingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "windowPerchingEnabled")
        refreshAccessibilityStatus()
        if !enabled { windowManager?.cancelAmbientBehaviors() }
    }

    func requestWindowPerchingPermission() {
        AccessibilityPermission.request()
        refreshAccessibilityStatus()
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = AccessibilityPermission.isTrusted
    }

    func deliverInvitation(_ candidate: InvitationCandidate) {
        schedulerSnapshot.now = Date()
        schedulerSnapshot = scheduler.snapshotAfterDelivery(schedulerSnapshot, petID: candidate.petID)
        pendingInvitations[candidate.petID] = candidate
        windowManager?.invite(candidate)
        recordScheduleExecution(candidate, outcome: .delivered)
        recordMetric("invitation_delivered", petID: candidate.petID)
        persistSchedulerState()
    }

    func acceptInvitation(for petID: PetID) {
        schedulerSnapshot.now = Date()
        schedulerSnapshot = scheduler.snapshotAfterAcceptance(schedulerSnapshot, petID: petID)
        pendingInvitations[petID] = nil
        windowManager?.dismissInvitation(petID)
        startPackage(for: petID)
        windowManager?.openDetail(petID, tab: 0)
        recordMetric("invitation_accepted", petID: petID)
        awardRelationship(.invitationAccepted, to: petID)
        persistSchedulerState()
    }

    func declineInvitation(for petID: PetID) {
        schedulerSnapshot.now = Date()
        schedulerSnapshot = scheduler.snapshotAfterDecline(schedulerSnapshot, petID: petID)
        pendingInvitations[petID] = nil
        windowManager?.dismissInvitation(petID)
        recordMetric("invitation_declined", petID: petID)
        persistSchedulerState()
    }

    func quietForOneHour() {
        schedulerSnapshot.quietUntil = Date().addingTimeInterval(3600)
        pendingInvitations.removeAll()
        windowManager?.dismissAllInvitations()
        persistSchedulerState()
    }

    func snoozeInvitationOneHour(for petID: PetID) {
        let candidate = pendingInvitations[petID]
        pendingInvitations[petID] = nil
        windowManager?.dismissInvitation(petID)
        if let candidate {
            recordScheduleExecution(candidate, outcome: .snoozed)
            let metadata = (try? context.fetch(FetchDescriptor<ScheduleMetadataEntity>())) ?? []
            let previousText = candidate.sourceScheduleID.flatMap { id in metadata.first(where: { $0.scheduleID == id })?.originalText }
            let previousCount: Int = {
                guard let previousText, previousText.hasPrefix("snooze:"),
                      let separator = previousText.firstIndex(of: "|") else { return 0 }
                return Int(previousText[previousText.index(previousText.startIndex, offsetBy: 7)..<separator]) ?? 0
            }()
            guard previousCount < 3 else {
                schedulerSuppressionReason = "这次邀请已暂缓三次，今天不再重复。"
                skipInvitationToday(for: petID)
                persistSchedulerState()
                return
            }
            addSchedule(
                for: petID,
                at: Date().addingTimeInterval(3600),
                recurrence: "once",
                content: candidate.body,
                usesSystemNotification: false,
                originalText: "snooze:\(previousCount + 1)|\(candidate.body)"
            )
        }
        persistSchedulerState()
    }

    func skipInvitationToday(for petID: PetID) {
        let candidate = pendingInvitations[petID]
        schedulerSnapshot.rejectedPetsToday.insert(petID)
        pendingInvitations[petID] = nil
        windowManager?.dismissInvitation(petID)
        if let candidate { recordScheduleExecution(candidate, outcome: .skipped) }
        persistSchedulerState()
    }

    func returnToPreviousApplication(for petID: PetID) {
        windowManager?.closeDetailAndReturn(petID)
    }

    private func focusCompleted() {
        schedulerSnapshot.focusSessionActive = false
        let focusPlans = ((try? context.fetch(FetchDescriptor<ScheduleEntity>())) ?? []).filter {
            $0.isEnabled && $0.triggerType == ScheduleTrigger.focusCompletion.rawValue
        }
        let now = Date()
        let planned = focusPlans.compactMap { schedule -> InvitationCandidate? in
            guard let petID = PetID(rawValue: schedule.petID) else { return nil }
            schedule.lastTriggeredAt = now
            return InvitationCandidate(
                petID: petID,
                priority: schedule.isCoursePlan ? .courseSchedule : .focusCompletion,
                createdAt: now,
                expiresAt: now.addingTimeInterval(15 * 60),
                title: "\(PetDefinition.definition(for: petID).name) 发现专注计时结束了",
                body: schedule.contentPreference,
                sourceScheduleID: schedule.id
            )
        }
        try? context.save()
        if !planned.isEmpty {
            schedulerSnapshot.now = now
            schedulerSnapshot.todayOnlyPet = todayOnlyPet
            if case let .deliver(winner) = scheduler.decide(candidates: planned, snapshot: schedulerSnapshot) {
                deliverInvitation(winner)
            }
            return
        }
        let candidates = PetID.allCases.filter { petID in
            let mode = ProactiveMode(rawValue: profile(for: petID).proactiveMode)
            return (mode == .naturalPause || mode == .occasionalInvite) && !isPetQuiet(petID, at: Date())
        }
        let pet = candidates.min { lhs, rhs in
            let left = profile(for: lhs).lastInteractionAt ?? .distantPast
            let right = profile(for: rhs).lastInteractionAt ?? .distantPast
            return left < right
        }
        guard let pet else { return }
        schedulerSnapshot.now = now
        schedulerSnapshot.todayOnlyPet = todayOnlyPet
        let definition = PetDefinition.definition(for: pet)
        let invitation = InvitationCandidate(
            petID: pet,
            priority: .focusCompletion,
            createdAt: now,
            expiresAt: now.addingTimeInterval(15 * 60),
            title: "\(definition.name) 发现专注计时结束了",
            body: "有一个一分钟的小世界。点开才会展开内容。"
        )
        if case let .deliver(winner) = scheduler.decide(candidates: [invitation], snapshot: schedulerSnapshot) {
            deliverInvitation(winner)
        }
    }

    private func persistMessageIfEnabled(petID: PetID, role: ChatRole, text: String, id: UUID = UUID()) {
        guard profile(for: petID).savesChatHistory, !temporaryChatPets.contains(petID) else { return }
        let threads = ((try? context.fetch(FetchDescriptor<ChatThreadEntity>())) ?? [])
            .filter { $0.petID == petID.rawValue }
            .sorted { $0.updatedAt > $1.updatedAt }
        let thread = threads.first ?? {
            let created = ChatThreadEntity(petID: petID)
            context.insert(created)
            return created
        }()
        let entity = ChatMessageEntity(threadID: thread.id, petID: petID, role: role, text: text)
        entity.id = id
        context.insert(entity)
        thread.updatedAt = Date()
        try? context.save()
    }

    private func upsertChatMetadata(messageID: UUID, state: ChatDeliveryState, correction: String? = nil) {
        let metadata = ((try? context.fetch(FetchDescriptor<ChatMessageMetadataEntity>())) ?? [])
            .first(where: { $0.messageID == messageID }) ?? {
                let created = ChatMessageMetadataEntity(messageID: messageID, state: state)
                context.insert(created)
                return created
            }()
        metadata.deliveryState = state.rawValue
        metadata.correctionText = correction
        metadata.updatedAt = Date()
        try? context.save()
    }

    private func recordInventoryReferences(for petID: PetID, in text: String) {
        let items = inventory(for: petID)
        let effects = (try? context.fetch(FetchDescriptor<InventoryEffectEntity>())) ?? []
        for item in items where text.localizedCaseInsensitiveContains(item.title) {
            guard let effect = effects.first(where: { $0.inventoryItemID == item.id && $0.petID == petID.rawValue }) else { continue }
            effect.referenceCount += 1
            effect.lastReferencedAt = Date()
        }
    }
}
