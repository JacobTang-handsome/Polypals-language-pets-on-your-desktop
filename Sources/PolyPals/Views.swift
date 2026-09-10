import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var apiKey = ""
    @State private var provider: ModelProvider = .deepSeek
    @State private var error: String?
    @State private var onboardingLevels: [PetID: CEFRLevel] = [.sol: .b1, .mousse: .a1, .ash: .c1]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("三个住在 Mac 桌面上的双语朋友")
                .font(.largeTitle.bold())
            Text("它们各自拥有性格、记忆和生活。你可以随时离开，也不会留下未完成任务。")
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                ForEach(PetDefinition.builtIns) { pet in
                    VStack(spacing: 10) {
                        PetPortrait(petID: pet.id, size: 64)
                        Text(pet.name).font(.headline)
                        Picker("语言等级", selection: Binding(
                            get: { onboardingLevels[pet.id] ?? pet.defaultLevel },
                            set: { onboardingLevels[pet.id] = $0 }
                        )) {
                            ForEach(CEFRLevel.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        Text((onboardingLevels[pet.id] ?? pet.defaultLevel).abilityDescription)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(pet.tagline).font(.caption).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 145)
                    .padding(12)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
                }
            }

            Picker("现在的精力", selection: $model.energyState) {
                ForEach(EnergyState.allCases) { state in
                    Label(state.title, systemImage: state.symbol).tag(state)
                }
            }
            .pickerStyle(.segmented)

            Picker("模型提供商", selection: $provider) {
                ForEach(ModelProvider.allCases) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            SecureField("\(provider.title) API Key（可稍后设置）", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            Text("密钥只保存在本机 Keychain。没有密钥时，126 张审核卡片仍可使用。")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }

            HStack {
                Spacer()
                Button("开始认识它们") {
                    do {
                        model.setModelProvider(provider)
                        for pet in PetDefinition.builtIns {
                            var language = model.languageProfile(for: pet.id)
                            let level = onboardingLevels[pet.id] ?? pet.defaultLevel
                            language.currentLevel = level
                            language.receptiveLevel = level
                            language.productiveLevel = level
                            model.updateLanguageProfile(language, for: pet.id)
                        }
                        if !apiKey.isEmpty { try model.saveAPIKey(apiKey) }
                        UserDefaults.standard.set(true, forKey: "completedOnboarding")
                        NSApp.keyWindow?.close()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(minWidth: 620, minHeight: 500)
    }
}

struct InvitationBubbleView: View {
    let candidate: InvitationCandidate
    let accept: () -> Void
    let decline: () -> Void
    let snoozeHour: () -> Void
    let skipToday: () -> Void
    let quietHour: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(candidate.title).font(.headline)
            Text(candidate.body).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("来一分钟", action: accept).buttonStyle(.borderedProminent)
                Button("今天不要", action: decline)
                Menu("稍后") {
                    Button("暂缓一小时", action: snoozeHour)
                    Button("今天跳过", action: skipToday)
                    Button("全部安静一小时", action: quietHour)
                }
            }.controlSize(.small)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct PetDetailView: View {
    @EnvironmentObject private var model: AppModel
    let petID: PetID
    @State private var selection = 0

    private var pet: PetDefinition { .definition(for: petID) }

    var body: some View {
        let profile = model.profile(for: petID)
        let relationship = model.relationshipLevel(for: petID)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                PetPortrait(petID: petID, size: 44)
                VStack(alignment: .leading) {
                    Text(pet.name).font(.title2.bold())
                    Text("\(pet.targetLanguage) · \(model.languageProfile(for: petID).currentLevel.displayName) · Lv.\(relationship.number) \(relationship.title)")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ProgressView(value: model.relationshipProgress(for: petID)).frame(width: 130)
                        Text(relationship.nextThreshold.map { "\(profile.relationshipPoints) / \($0)" } ?? "\(profile.relationshipPoints)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Picker("精力", selection: $model.energyState) {
                    ForEach(EnergyState.allCases) { state in Text(state.title).tag(state) }
                }
                .frame(width: 130)
            }
            .padding()

            TabView(selection: $selection) {
                NowView(petID: petID).tabItem { Label("现在", systemImage: "sparkles") }.tag(0)
                ChatLauncherView(petID: petID).tabItem { Label("聊天", systemImage: "bubble.left.and.bubble.right") }.tag(1)
                BackpackView(petID: petID).tabItem { Label("背包", systemImage: "backpack") }.tag(2)
                PlansView(petID: petID).tabItem { Label("计划", systemImage: "calendar") }.tag(3)
                CharacterView(petID: petID).tabItem { Label("角色", systemImage: "slider.horizontal.3") }.tag(4)
            }
        }
        .frame(minWidth: 620, minHeight: 480)
        .onAppear { selection = model.requestedTab[petID, default: 0] }
        .onChange(of: model.requestedTab[petID, default: 0]) { _, value in selection = value }
    }

}

struct ChatLauncherView: View {
    @EnvironmentObject private var model: AppModel
    let petID: PetID
    private var pet: PetDefinition { .definition(for: petID) }
    private var theme: PetChatTheme { .forPet(petID) }

    var body: some View {
        VStack(spacing: 18) {
            PetPortrait(petID: petID, size: 92)
            Text(theme.title).font(.title2.bold())
            Text(model.relationshipGreeting(for: petID))
                .font(.callout)
                .foregroundStyle(theme.accent)
            Text("这是一个靠近桌宠的小聊天框。它不会把你带进另一套复杂界面。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let last = model.chatLines[petID]?.last(where: { !$0.text.isEmpty }) {
                Text(last.text).font(.callout).lineLimit(3)
                    .padding(14).frame(maxWidth: 420)
                    .background(theme.petBubble, in: RoundedRectangle(cornerRadius: 18))
            }
            Button("打开 \(pet.name) 的小聊天框") { model.openChatPanel(for: petID) }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.opacity(0.45))
    }
}

struct NowView: View {
    @EnvironmentObject private var model: AppModel
    let petID: PetID
    @State private var packageCount = 2

    var body: some View {
        VStack(spacing: 18) {
            Text(model.todaySummary(for: petID))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            let words = model.weeklyEncounteredWords(for: petID)
            if !words.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("本周遇见过").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(words.joined(separator: "  ·  "))
                        .font(.caption)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            }
            if model.packageFinished.contains(petID) {
                ContentUnavailableView(
                    "这次就到这里",
                    systemImage: "checkmark.circle",
                    description: Text("没有未完成任务。你可以轻松回去，也可以主动再来一个。")
                )
                HStack {
                    Button("回去工作") { model.returnToPreviousApplication(for: petID) }
                    Button("再来一个") { model.startPackage(for: petID, count: 1) }
                        .buttonStyle(.borderedProminent)
                }
            } else if let card = model.currentCard(for: petID) {
                CardView(card: card, petID: petID)
            } else {
                Text(PetDefinition.definition(for: petID).tagline)
                    .font(.title3)
                Stepper("这次 \(packageCount) 张 · 约 \(packageCount * 60) 秒", value: $packageCount, in: 1...3)
                    .frame(width: 260)
                Button("给我一个有限套餐") { model.startPackage(for: petID, count: packageCount) }
                    .buttonStyle(.borderedProminent)
                HStack {
                    Button("这次更简单") {
                        model.startPackage(for: petID, count: packageCount, temporaryLevel: model.languageProfile(for: petID).currentLevel.lower)
                    }
                    Button("这次更困难") {
                        model.startPackage(for: petID, count: packageCount, temporaryLevel: model.languageProfile(for: petID).currentLevel.higher)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(24)
    }
}

struct CardView: View {
    @EnvironmentObject private var model: AppModel
    let card: GeneratedCard
    let petID: PetID
    @State private var selectedChoice: String?
    @State private var showHelp = false
    @State private var lastFeedback: CardFeedbackType?
    @StateObject private var speaker = CardSpeaker()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(card.type.title, systemImage: card.type.symbol)
                let source = model.cardSource(card)
                if source == "ai" || source == "pack" {
                    Text(source == "ai" ? "AI 生成" : "内容包")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.12), in: Capsule())
                }
                Spacer()
                Label("约 \(card.estimatedSeconds) 秒", systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
            Text(card.hook).font(.headline)
            Text(card.targetText)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .textSelection(.enabled)
            Text(card.prompt)

            if card.type == .picturePrompt {
                BundledPetPicture(petID: petID)
                    .frame(maxHeight: 130)
                    .accessibilityLabel("\(PetDefinition.definition(for: petID).name) 的看图表达提示")
            }

            if card.type == .listening {
                HStack {
                    Button("播放") { speaker.speak(card.targetText, locale: PetDefinition.definition(for: petID).locale, slow: false) }
                    Button("慢速") { speaker.speak(card.targetText, locale: PetDefinition.definition(for: petID).locale, slow: true) }
                }
            }

            if !card.choices.isEmpty {
                HStack {
                    ForEach(card.choices, id: \.self) { choice in
                        Button(choice) { selectedChoice = choice }
                            .buttonStyle(.bordered)
                    }
                }
                if let selectedChoice {
                    Label(selectedChoice == card.answer ? "就是这个" : "可以再看看提示", systemImage: selectedChoice == card.answer ? "checkmark.circle.fill" : "arrow.counterclockwise")
                        .foregroundStyle(selectedChoice == card.answer ? .green : .secondary)
                }
            }

            DisclosureGroup("中文提示", isExpanded: $showHelp) {
                Text(card.chineseHelp).padding(.top, 6)
            }
            HStack(spacing: 8) {
                Text("这张卡片")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("喜欢") { model.recordCardFeedback(.liked, for: card); lastFeedback = .liked }
                Button("太简单") { model.recordCardFeedback(.tooEasy, for: card); lastFeedback = .tooEasy }
                Button("太难") { model.recordCardFeedback(.tooHard, for: card); lastFeedback = .tooHard }
                Button("不想再看这类") { model.recordCardFeedback(.hideSimilar, for: card); lastFeedback = .hideSimilar }
                if let lastFeedback {
                    Button("撤销") { model.undoCardFeedback(lastFeedback, for: card); self.lastFeedback = nil }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if let title = card.sourceTitle, let raw = card.sourceURL, let url = URL(string: raw) {
                Link("来源：\(title)", destination: url).font(.caption)
            }
            Spacer()
            HStack {
                Button("划走") { model.advanceCard(for: petID, skipped: true) }
                Button("收藏") { model.favoriteCurrentCard(for: petID) }
                if model.hasAPIKey && card.type != .culture {
                    Button("换一个变化") { model.replaceCurrentCardWithAI(for: petID) }
                }
                Spacer()
                Button("完成这一张") { model.advanceCard(for: petID) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(maxWidth: 620, minHeight: 390)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 20))
    }
}

@MainActor
final class CardSpeaker: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, locale: String, slow: Bool) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: locale)
        utterance.rate = slow ? 0.35 : AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    let petID: PetID

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("方式", selection: correctionBinding) {
                    ForEach(CorrectionMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                Spacer()
                Text("\(model.modelProvider.title) · \(model.modelID)")
                    .font(.caption).foregroundStyle(.secondary)
                Button("保存为共同记忆") { model.requestMemoryProposals(for: petID) }
                    .disabled(!model.hasAPIKey || model.chatLines[petID, default: []].isEmpty)
            }
            DisclosureGroup("本次请求会带什么") {
                Text(model.contextPreview(for: petID))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.chatLines[petID, default: []]) { line in
                            HStack {
                                if line.role == .user { Spacer(minLength: 70) }
                                VStack(alignment: line.role == .user ? .trailing : .leading, spacing: 3) {
                                    ChatBubbleText(line: line)
                                        .padding(10)
                                        .background(line.role == .user ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                    if !line.text.isEmpty {
                                        HStack(spacing: 10) {
                                            Button(line.isFavorite ? "已收藏" : "收藏这句") { model.favoriteChatLine(line, petID: petID) }
                                                .disabled(line.isFavorite)
                                            Button("制成复习卡") { model.makeReviewCard(from: line, petID: petID) }
                                        }
                                        .buttonStyle(.plain).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                if line.role == .assistant { Spacer(minLength: 70) }
                            }
                            .id(line.id)
                        }
                    }
                }
                .onChange(of: model.chatLines[petID, default: []].count) { _, _ in
                    if let id = model.chatLines[petID]?.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }

            if let error = model.chatErrors[petID] {
                HStack {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("手动重试") { model.retryLastChat(for: petID) }
                        .disabled(model.isChatting.contains(petID))
                }
            }
            if !model.memoryProposals[petID, default: []].isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("确认后才会成为长期记忆").font(.caption.bold())
                    ForEach(model.memoryProposals[petID, default: []]) { proposal in
                        HStack {
                            TextField("可在保存前编辑", text: Binding(
                                get: {
                                    model.memoryProposals[petID]?.first(where: { $0.id == proposal.id })?.content
                                        ?? proposal.content
                                },
                                set: { model.updateMemoryProposal(proposal.id, petID: petID, content: $0) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            Spacer()
                            Button("保存") { model.confirmMemory(proposal, petID: petID) }
                        }
                    }
                }
                .padding(8).background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                TextField("随时说一句……", text: Binding(
                    get: { model.chatDrafts[petID, default: ""] },
                    set: { model.chatDrafts[petID] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.sendChat(to: petID) }
                Button("发送") { model.sendChat(to: petID) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isChatting.contains(petID))
            }
        }
        .padding()
    }

    private var correctionBinding: Binding<CorrectionMode> {
        Binding(
            get: { CorrectionMode(rawValue: model.profile(for: petID).correctionMode) ?? .casual },
            set: {
                model.profile(for: petID).correctionMode = $0.rawValue
                try? model.container.mainContext.save()
                model.reloadProfiles()
            }
        )
    }
}

private struct ChatBubbleText: View {
    let line: ChatLine

    private var parts: (answer: String, correction: String?) {
        guard line.role == .assistant,
              let marker = line.text.range(of: "【可选纠错】") else {
            return (line.text, nil)
        }
        let answer = String(line.text[..<marker.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let correction = String(line.text[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (answer, correction.isEmpty ? nil : correction)
    }

    var body: some View {
        let value = parts
        VStack(alignment: .leading, spacing: 6) {
            Text(ChatMarkdownRenderer.attributed(value.answer.isEmpty ? "…" : value.answer))
                .textSelection(.enabled)
            if let correction = value.correction {
                DisclosureGroup("可选纠错") {
                    Text(ChatMarkdownRenderer.attributed(correction))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
                .font(.caption)
            }
        }
    }
}

struct BackpackView: View {
    @EnvironmentObject private var model: AppModel
    let petID: PetID
    @State private var editingMemory: PetMemoryEntity?
    @State private var editedMemoryText = ""
    @State private var confirmingClear = false
    @State private var inventoryFilter = "all"

    var body: some View {
        HStack(spacing: 18) {
            GroupBox("共同收藏") {
                VStack {
                    Picker("筛选", selection: $inventoryFilter) {
                        Text("全部").tag("all")
                        Text("卡片").tag("card")
                        Text("聊天").tag("chat")
                        Text("复习卡").tag("review-card")
                        Text("礼物").tag("gift")
                    }.pickerStyle(.menu)
                    List(filteredInventory) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.title).font(.headline)
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { model.deleteInventoryItem(item) } label: { Image(systemName: "trash") }
                        }
                    }
                }
            }
            GroupBox("已确认记忆") {
                List(model.memories(for: petID)) { memory in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(memory.content)
                            Text(memory.type).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            editingMemory = memory
                            editedMemoryText = memory.content
                        } label: { Image(systemName: "pencil") }
                        Button(role: .destructive) { model.deleteMemory(memory) } label: { Image(systemName: "trash") }
                    }
                }
            }
        }
        .padding()
        .sheet(item: $editingMemory) { memory in
            VStack(alignment: .leading, spacing: 14) {
                Text("编辑共同记忆").font(.headline)
                TextEditor(text: $editedMemoryText).frame(minHeight: 100)
                HStack {
                    Button("取消") { editingMemory = nil }
                    Spacer()
                    Button("保存") {
                        model.updateMemory(memory, content: editedMemoryText)
                        editingMemory = nil
                    }.buttonStyle(.borderedProminent)
                }
            }.padding().frame(width: 420)
        }
        .toolbar {
            Button("清空这只宠物的记忆", role: .destructive) { confirmingClear = true }
        }
        .confirmationDialog("清空这只宠物的所有已确认记忆？", isPresented: $confirmingClear) {
            Button("清空记忆", role: .destructive) { model.clearMemories(for: petID) }
        }
    }

    private var filteredInventory: [InventoryItemEntity] {
        let items = model.inventory(for: petID)
        return inventoryFilter == "all" ? items : items.filter { $0.kind == inventoryFilter }
    }
}

struct PlansView: View {
    @EnvironmentObject private var model: AppModel
    let petID: PetID
    @State private var fireDate = Date().addingTimeInterval(3600)
    @State private var content = "带来一个一分钟的故事"
    @State private var recurrence = "daily"
    @State private var usesSystemNotification = false
    @State private var isCoursePlan = false
    @State private var naturalLanguagePlan = ""
    @State private var parsedPlan: ParsedScheduleDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("应用内专注计时器") {
                HStack {
                    if model.focusTimer.isRunning {
                        Text(model.focusTimer.formattedRemaining).font(.title.monospacedDigit())
                        Button("停止") { model.stopFocus() }
                    } else {
                        Button("专注 25 分钟") {
                            model.startFocus(minutes: 25)
                        }
                        Button("专注 50 分钟") {
                            model.startFocus(minutes: 50)
                        }
                    }
                }
            }
            GroupBox("定时提醒") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("例如：每周三下午六点让 Mousse 带来复习", text: $naturalLanguagePlan)
                        Button("解析") { parsedPlan = ScheduleParser().parse(naturalLanguagePlan) }
                    }
                    if let parsedPlan {
                        Text(parsedPlan.clarification ?? "已识别：\(parsedPlan.recurrence ?? "单次") · \(parsedPlan.fireDate?.formatted(date: .abbreviated, time: .shortened) ?? "专注结束") · 置信度 \(Int(parsedPlan.confidence * 100))%")
                            .font(.caption).foregroundStyle(parsedPlan.confidence >= 0.75 ? Color.secondary : Color.orange)
                        Button("确认并添加这条计划") {
                            guard parsedPlan.confidence >= 0.75, let targetPet = parsedPlan.petID ?? PetID(rawValue: petID.rawValue) else { return }
                            model.addParsedSchedule(parsedPlan, fallbackPetID: targetPet, usesSystemNotification: usesSystemNotification, isCoursePlan: isCoursePlan, originalText: naturalLanguagePlan)
                            self.parsedPlan = nil; naturalLanguagePlan = ""
                        }
                        .disabled(parsedPlan.confidence < 0.75 || (parsedPlan.trigger == .calendar && parsedPlan.fireDate == nil))
                    }
                    Picker("重复", selection: $recurrence) {
                        Text("每天").tag("daily")
                        Text("每周").tag("weekly")
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Toggle("使用系统通知", isOn: $usesSystemNotification)
                        Toggle("课程前复习（高优先级）", isOn: $isCoursePlan)
                    }
                    HStack {
                        DatePicker(
                            recurrence == "weekly" ? "星期与时间" : "时间",
                            selection: $fireDate,
                            displayedComponents: recurrence == "weekly" ? [.date, .hourAndMinute] : [.hourAndMinute]
                        )
                        TextField("内容", text: $content)
                        Button("添加") {
                            model.addSchedule(
                                for: petID,
                                at: fireDate,
                                recurrence: recurrence,
                                content: content,
                                usesSystemNotification: usesSystemNotification,
                                isCoursePlan: isCoursePlan
                            )
                        }
                    }
                }
            }
            List(model.schedules(for: petID)) { schedule in
                HStack {
                    Toggle("", isOn: Binding(
                        get: { schedule.isEnabled },
                        set: { model.setScheduleEnabled(schedule, enabled: $0) }
                    ))
                    .labelsHidden()
                    VStack(alignment: .leading) {
                        Text(schedule.contentPreference)
                        Text("\(schedule.recurrence ?? "单次") · \(schedule.usesSystemNotification ? "系统通知" : "桌宠动作")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) { model.deleteSchedule(schedule) } label: { Image(systemName: "trash") }
                }
            }
            if let reason = model.schedulerSuppressionReason {
                Text("最近一次没有主动出现：\(reason)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GroupBox("执行历史") {
                ForEach(model.scheduleHistory(for: petID)) { execution in
                    HStack {
                        Text(execution.firedAt.formatted(date: .abbreviated, time: .shortened))
                        Text(execution.outcome)
                        if let reason = execution.suppressionReason { Text(reason).foregroundStyle(.secondary) }
                        Spacer()
                    }.font(.caption)
                }
            }
        }
        .padding()
    }
}

struct CharacterView: View {
    @EnvironmentObject private var model: AppModel
    let petID: PetID
    @State private var confirmingReset = false

    var body: some View {
        let profile = model.profile(for: petID)
        let relationship = model.relationshipLevel(for: petID)
        let language = model.languageProfile(for: petID)
        Form {
            Section("我们的关系") {
                LabeledContent("熟悉等级", value: "Lv.\(relationship.number) \(relationship.title)")
                ProgressView(value: model.relationshipProgress(for: petID))
                LabeledContent("熟悉度", value: relationship.nextThreshold.map { "\(profile.relationshipPoints) / \($0)" } ?? "\(profile.relationshipPoints) · 已达最高等级")
                LabeledContent("认识天数", value: "\(max(1, (Calendar.current.dateComponents([.day], from: model.firstMetAt(for: petID), to: Date()).day ?? 0) + 1)) 天")
                LabeledContent("共同记忆", value: "\(model.memories(for: petID).count)")
                LabeledContent("收藏与礼物", value: "\(model.inventory(for: petID).count)")
                Text("熟悉度不会下降；跳过、拒绝或休眠都不会扣分。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("主动程度", selection: binding(\.proactiveMode, transform: { ProactiveMode(rawValue: $0) ?? .manual }, reverse: \.rawValue)) {
                ForEach(ProactiveMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            Toggle("允许宠物在窗口边缘活动", isOn: Binding(
                get: { model.windowPerchingEnabled },
                set: { model.setWindowPerchingEnabled($0) }
            ))
            if model.windowPerchingEnabled {
                if model.accessibilityTrusted {
                    Label("已可识别并跟随其他应用窗口", systemImage: "checkmark.shield")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("未授权时会自动降级为在屏幕边缘活动，不会影响其他功能。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("授予辅助功能权限") { model.requestWindowPerchingPermission() }
                    }
                }
            }
            Section("语言能力") {
                Picker("当前等级", selection: languageBinding(\.currentLevel)) {
                    ForEach(CEFRLevel.allCases) { Text($0.displayName).tag($0) }
                }
                Text(language.currentLevel.abilityDescription).font(.caption).foregroundStyle(.secondary)
                Picker("理解等级", selection: languageBinding(\.receptiveLevel)) {
                    ForEach(CEFRLevel.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("表达等级", selection: languageBinding(\.productiveLevel)) {
                    ForEach(CEFRLevel.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("难度模式", selection: languageBinding(\.difficultyMode)) {
                    ForEach(DifficultyMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("纠错方式", selection: languageBinding(\.correctionMode)) {
                    ForEach(CorrectionMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                HStack {
                    Text("中文帮助")
                    Slider(value: languageBinding(\.chineseHelpRatio), in: 0...0.7, step: 0.05)
                    Text("\(Int(language.chineseHelpRatio * 100))%")
                }
                if let suggested = model.adaptiveLevelSuggestions[petID] {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("根据近期反馈，可以尝试 \(suggested.displayName)。只有你确认后才会修改。")
                        HStack {
                            Button("采用建议") { model.acceptAdaptiveLevelSuggestion(for: petID) }
                            Button("保持当前等级") { model.dismissAdaptiveLevelSuggestion(for: petID) }
                        }
                    }
                }
            }
            HStack {
                Text("显示大小")
                Slider(value: binding(\.size), in: 80...192, step: 8)
                Text("\(Int(profile.size)) pt")
            }
            Toggle("保存聊天历史", isOn: binding(\.savesChatHistory))
            Toggle("在所有桌面空间显示", isOn: binding(\.appearsOnAllSpaces))
            Toggle("显示这只宠物", isOn: binding(\.isVisible))
            Toggle("休眠", isOn: binding(\.isSleeping))
            Stepper("安静开始：\(profile.quietStartHour):00", value: binding(\.quietStartHour), in: 0...23)
            Stepper("安静结束：\(profile.quietEndHour):00", value: binding(\.quietEndHour), in: 0...23)
            LabeledContent("语言", value: profile.targetLanguage)
            Button("重置这只宠物的数据", role: .destructive) { confirmingReset = true }
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog("清除这只宠物的聊天、记忆、收藏、计划和设置？角色本身会保留。", isPresented: $confirmingReset) {
            Button("重置", role: .destructive) { Task { await model.resetPet(petID) } }
        }
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<PetProfileEntity, Value>) -> Binding<Value> {
        Binding(
            get: { model.profile(for: petID)[keyPath: keyPath] },
            set: {
                model.profile(for: petID)[keyPath: keyPath] = $0
                try? model.container.mainContext.save()
                model.reloadProfiles()
                model.windowManager?.refresh(petID)
            }
        )
    }

    private func languageBinding<Value>(_ keyPath: WritableKeyPath<LanguageProfile, Value>) -> Binding<Value> {
        Binding(
            get: { model.languageProfile(for: petID)[keyPath: keyPath] },
            set: {
                var value = model.languageProfile(for: petID)
                value[keyPath: keyPath] = $0
                model.updateLanguageProfile(value, for: petID)
            }
        )
    }

    private func binding<Value, UIValue>(
        _ keyPath: ReferenceWritableKeyPath<PetProfileEntity, Value>,
        transform: @escaping (Value) -> UIValue,
        reverse: @escaping (UIValue) -> Value
    ) -> Binding<UIValue> {
        Binding(
            get: { transform(model.profile(for: petID)[keyPath: keyPath]) },
            set: { binding(keyPath).wrappedValue = reverse($0) }
        )
    }
}

struct GlobalSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var apiKey = ""
    @State private var modelText = ""
    @State private var status: String?
    @State private var importingPack = false
    @State private var installingPlugin = false

    var body: some View {
        Form {
            Section("模型") {
                Picker("提供商", selection: Binding(
                    get: { model.modelProvider },
                    set: { model.setModelProvider($0); modelText = $0.defaultModel; apiKey = "" }
                )) {
                    ForEach(ModelProvider.allCases) { provider in Text(provider.title).tag(provider) }
                }
                .pickerStyle(.segmented)
                Picker("推荐模型", selection: $modelText) {
                    ForEach(model.modelProvider.availableModels, id: \.self) { Text($0).tag($0) }
                }
                SecureField(model.hasAPIKey ? "已保存 \(model.modelProvider.title) Key；输入新值以替换" : "\(model.modelProvider.title) API Key", text: $apiKey)
                TextField("模型 ID", text: $modelText)
                Picker("推理强度", selection: Binding(
                    get: { model.reasoningEffort },
                    set: { model.setReasoningEffort($0) }
                )) {
                    ForEach(ReasoningEffort.allCases) { effort in Text(effort.title).tag(effort) }
                }
                HStack {
                    Button("保存") {
                        do {
                            if !apiKey.isEmpty { try model.saveAPIKey(apiKey); apiKey = "" }
                            model.setModelID(modelText)
                            status = "已保存在本机。"
                        } catch { status = error.localizedDescription }
                    }
                    Button("删除 API Key", role: .destructive) {
                        do { try model.deleteAPIKey(); status = "API Key 已删除。" }
                        catch { status = error.localizedDescription }
                    }
                    Button("测试连接") {
                        model.setModelID(modelText)
                        model.testModelConnection()
                    }
                    .disabled(!model.hasAPIKey)
                }
                if let connection = model.modelConnectionStatus { Text(connection).font(.caption).foregroundStyle(.secondary) }
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            Section("内容") {
                Toggle("智能补充卡片", isOn: Binding(
                    get: { model.smartCardSupplement },
                    set: { model.setSmartCardSupplement($0) }
                ))
                Text("离线包含126张审核卡片；开启后每个套餐最多联网生成一张非文化卡片，并缓存到本机。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("安装 .polypals-pack") { installingPlugin = true }
                    Button("导入旧版内容 JSON") { importingPack = true }
                }
                if let report = model.pendingPluginPreview {
                    VStack(alignment: .leading, spacing: 5) {
                        if let manifest = report.manifest {
                            Text("插件安装预览").font(.headline)
                            Text("\(manifest.name) · v\(manifest.version) · \(manifest.kind.rawValue)")
                            Text("作者：\(manifest.author) · 许可：\(manifest.license)")
                            Text("语言：\(manifest.languages.joined(separator: ", ")) · 等级：\(manifest.levels.joined(separator: ", "))")
                            Text("能力：\(manifest.capabilities.joined(separator: ", "))")
                        }
                        ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                            Text("\(issue.severity.rawValue): \(issue.message)")
                                .font(.caption).foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                        }
                        HStack {
                            Button("确认安装") { model.confirmPluginInstall() }.disabled(!report.isValid)
                            Button("取消") { model.cancelPluginPreview() }
                        }
                    }
                    .padding(10)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                if let preview = model.pendingContentPackPreview {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(preview.isUpgrade ? "内容包升级预览" : "内容包导入预览").font(.headline)
                        Text("\(preview.manifest.title) · v\(preview.manifest.version) · \(preview.cardCount) 张卡片")
                        Text("作者：\(preview.manifest.author) · 语言：\(preview.manifest.language) · 冲突：\(preview.conflictCount)")
                            .font(.caption).foregroundStyle(preview.conflictCount == 0 ? Color.secondary : Color.orange)
                        Text(preview.typeCounts.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.title) \($0.value)" }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(preview.isUpgrade ? "确认升级" : "确认导入") { model.confirmContentPackImport() }
                                .disabled(preview.conflictCount > 0)
                            Button("取消") { model.cancelContentPackImport() }
                        }
                    }
                    .padding(10)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                if let packStatus = model.contentPackStatus {
                    Text(packStatus).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.contentPacks()) { pack in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { pack.isEnabled },
                            set: { model.setContentPack(pack, enabled: $0) }
                        )) {
                            VStack(alignment: .leading) {
                                Text(pack.title)
                                Text("v\(pack.version) · \(pack.author)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button(role: .destructive) { model.deleteContentPack(pack) } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                ForEach(model.installedPlugins) { plugin in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { plugin.enabled },
                            set: { model.setPlugin(plugin, enabled: $0) }
                        )) {
                            VStack(alignment: .leading) {
                                Text(plugin.manifest.name)
                                Text("\(plugin.manifest.kind.rawValue) · v\(plugin.manifest.version) · \(plugin.manifest.license)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let issue = plugin.issues.first {
                                    Text("已自动停用：\(issue.message)").font(.caption).foregroundStyle(.red)
                                }
                            }
                        }
                        Button("查看来源") { NSWorkspace.shared.activateFileViewerSelecting([plugin.directory]) }
                        Button(role: .destructive) { model.deletePlugin(plugin) } label: { Image(systemName: "trash") }
                    }
                }
                Divider()
                Text("内容偏好").font(.headline)
                ForEach(PetID.allCases) { pet in
                    HStack {
                        Text(PetDefinition.definition(for: pet).name)
                        Spacer()
                        Text("挑战倾向 \(CardRepository(context: model.container.mainContext).selectionPreferences(for: pet).challengeBias)")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("重置") { model.clearCardFeedback(for: pet) }
                    }
                }
            }
            Section("防打扰") {
                Toggle("演示模式", isOn: Binding(get: { model.presentationMode }, set: { _ in model.togglePresentationMode() }))
                Picker("今天只见", selection: $model.todayOnlyPet) {
                    Text("全部宠物").tag(PetID?.none)
                    ForEach(PetID.allCases) { pet in Text(PetDefinition.definition(for: pet).name).tag(PetID?.some(pet)) }
                }
                Stepper("每天全局主动邀请：\(model.globalDailyInvitationLimit) 次", value: Binding(
                    get: { model.globalDailyInvitationLimit },
                    set: { model.setGlobalDailyInvitationLimit($0) }
                ), in: 0...6)
                if let reason = model.schedulerSnapshot.lastGlobalInvitationAt {
                    Text("上次主动出现：\(reason.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("通知") {
                Text("系统通知只在你第一次确认‘使用系统通知’的计划时申请。拒绝权限不会删除计划，应用仍可在运行时让宠物出现。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("每只宠物的安静时间和通知开关位于对应的‘角色’页；全局冷却、每日上限和执行原因在这里统一管理。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("隐私") {
                if let warning = model.startupDataWarning {
                    Label(warning, systemImage: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
                }
                Text("不读取屏幕、代码或按键；聊天只发送当前消息、最近会话和你已确认的记忆。模型请求固定使用 store: false。")
                    .font(.caption)
                Button("复制本地统计 CSV") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.exportMetrics(), forType: .string) }
                Button("清空本地统计", role: .destructive) { model.clearMetrics() }
            }
            Section("关于") {
                LabeledContent("版本", value: appVersion)
                Text("原生 macOS 14+ · Apple Silicon · 直接分发测试版")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 580, height: 560)
        .onAppear { modelText = model.modelID }
        .onChange(of: model.todayOnlyPet) { _, value in model.setTodayOnlyPet(value) }
        .fileImporter(isPresented: $importingPack, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            guard let data = try? Data(contentsOf: url) else {
                model.contentPackStatus = "无法读取内容包。"
                return
            }
            model.previewContentPack(data)
        }
        .fileImporter(isPresented: $installingPlugin, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            model.previewPluginPack(from: url)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

extension PetID {
    var emoji: String {
        switch self { case .sol: "🦊"; case .mousse: "🐆"; case .ash: "🦉" }
    }
}

struct PetPortrait: View {
    let petID: PetID
    let size: CGFloat

    var body: some View {
        BundledPetPicture(petID: petID)
            .frame(width: size, height: size)
            .accessibilityLabel("\(PetDefinition.definition(for: petID).name) 角色形象")
    }
}

private struct BundledPetPicture: View {
    let petID: PetID

    var body: some View {
        if let url = PetAssetCatalog.picturePromptURL(for: petID),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Text(petID.emoji)
                .font(.largeTitle)
        }
    }
}

private extension CardType {
    var symbol: String {
        switch self {
        case .expression: "quote.bubble"
        case .dialogue: "theatermasks"
        case .culture: "globe"
        case .listening: "ear"
        case .scenario: "person.2"
        case .confusingWords: "arrow.left.arrow.right"
        case .picturePrompt: "photo"
        }
    }
}
