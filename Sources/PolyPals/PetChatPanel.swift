import AppKit
import SwiftUI

private final class PetChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

struct PetChatTheme {
    let accent: Color
    let background: Color
    let petBubble: Color
    let userBubble: Color
    let title: String
    let placeholder: String

    static func forPet(_ petID: PetID) -> Self {
        switch petID {
        case .sol:
            .init(accent: Color(red: 0.86, green: 0.35, blue: 0.20), background: Color(red: 1, green: 0.94, blue: 0.88), petBubble: Color.white.opacity(0.82), userBubble: Color(red: 1, green: 0.83, blue: 0.68), title: "Sol 的小角落", placeholder: "跟 Sol 说点什么……")
        case .mousse:
            .init(accent: Color(red: 0.62, green: 0.39, blue: 0.10), background: Color(red: 0.98, green: 0.95, blue: 0.84), petBubble: Color.white.opacity(0.9), userBubble: Color(red: 0.91, green: 0.82, blue: 0.61), title: "Mousse 的咖啡桌", placeholder: "给 Mousse 一句话……")
        case .ash:
            .init(accent: Color(red: 0.23, green: 0.35, blue: 0.55), background: Color(red: 0.88, green: 0.91, blue: 0.96), petBubble: Color.white.opacity(0.85), userBubble: Color(red: 0.70, green: 0.78, blue: 0.91), title: "Ash 的夜间便签", placeholder: "Leave Ash a thought…")
        }
    }
}

@MainActor
final class PetChatPanelController: NSWindowController, NSWindowDelegate {
    private let petID: PetID
    private weak var ownerPanel: NSPanel?
    private let onClose: () -> Void

    init(petID: PetID, model: AppModel, ownerPanel: NSPanel, onClose: @escaping () -> Void) {
        self.petID = petID
        self.ownerPanel = ownerPanel
        self.onClose = onClose
        let window = PetChatPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let root = PetChatPanelView(petID: petID, close: { [weak window] in window?.close() })
            .environmentObject(model)
            .frame(minWidth: 420, idealWidth: 440, minHeight: 500, idealHeight: 540)
        window.contentViewController = NSHostingController(rootView: root)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        window.minSize = NSSize(width: 440, height: 540)
        window.maxSize = NSSize(width: 440, height: 540)
        window.setContentSize(NSSize(width: 440, height: 540))
        super.init(window: window)
        window.delegate = self
        reposition()
        ownerPanel.addChildWindow(window, ordered: .above)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        if let ownerPanel, let window, window.parent !== ownerPanel {
            ownerPanel.addChildWindow(window, ordered: .above)
        }
        reposition()
        window?.makeKeyAndOrderFront(nil)
    }

    func reposition() {
        guard let ownerPanel, let window else { return }
        let screen = ownerPanel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let gap: CGFloat = 12
        let right = ownerPanel.frame.maxX + gap
        let left = ownerPanel.frame.minX - window.frame.width - gap
        let x = right + window.frame.width <= visible.maxX ? right : max(visible.minX, left)
        let y = min(visible.maxY - window.frame.height, max(visible.minY, ownerPanel.frame.midY - window.frame.height / 2))
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func windowWillClose(_ notification: Notification) {
        if let window { ownerPanel?.removeChildWindow(window) }
        AppModel.shared.discardEphemeralChat(for: petID)
        onClose()
    }
}

struct PetChatPanelView: View {
    @EnvironmentObject private var model: AppModel
    let petID: PetID
    let close: () -> Void
    @State private var showContext = false
    @State private var isEditing = false
    @State private var favoriteLine: ChatLine?

    private var theme: PetChatTheme { .forPet(petID) }
    private var pet: PetDefinition { .definition(for: petID) }
    private var relationship: RelationshipLevel { model.relationshipLevel(for: petID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.chatLines[petID, default: []]) { line in
                            bubble(line)
                                .id(line.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.chatLines[petID, default: []].count) { _, _ in
                    if let id = model.chatLines[petID]?.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            if let error = model.chatErrors[petID] {
                HStack {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("重试") { model.retryLastChat(for: petID) }
                }
                .padding(.horizontal, 16)
            }
            composer
        }
        .background(theme.background.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(theme.accent.opacity(0.22), lineWidth: 1))
        .tint(theme.accent)
        .frame(minWidth: 420, minHeight: 500)
        .sheet(item: $favoriteLine) { line in
            FavoriteChatEditor(line: line, petID: petID)
                .environmentObject(model)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            PetPortrait(petID: petID, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.title).font(.headline).lineLimit(1)
                Text("Lv.\(relationship.number) · \(relationship.title)").font(.caption2).foregroundStyle(.secondary)
                Text(model.relationshipGreeting(for: petID)).font(.caption2).foregroundStyle(theme.accent).lineLimit(2)
            }
            Spacer()
            if model.temporaryChatPets.contains(petID) {
                Label("本次不保存", systemImage: "eye.slash").font(.caption2).foregroundStyle(.secondary)
            }
            Menu {
                Toggle("本次聊天不保存", isOn: Binding(
                    get: { model.temporaryChatPets.contains(petID) },
                    set: { model.setTemporaryChat($0, for: petID) }
                ))
                Button("上下文预览") { showContext = true }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("关闭聊天")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .sheet(isPresented: $showContext) {
            VStack(alignment: .leading, spacing: 12) {
                Text("这次会带什么").font(.headline)
                Text(model.contextPreview(for: petID)).font(.callout).foregroundStyle(.secondary)
                if !model.memories(for: petID).isEmpty {
                    Text("共同记忆").font(.caption.bold())
                    ForEach(model.memories(for: petID).prefix(6)) { memory in
                        Toggle(memory.content, isOn: Binding(
                            get: { !model.excludedContextMemoryIDs[petID, default: []].contains(memory.id) },
                            set: { model.setMemoryIncludedInNextRequest(memory.id, petID: petID, included: $0) }
                        ))
                    }
                }
                if !model.inventory(for: petID).isEmpty {
                    Text("背包物品").font(.caption.bold())
                    ForEach(model.inventory(for: petID).prefix(6)) { item in
                        Toggle(item.title, isOn: Binding(
                            get: { !model.excludedContextItemIDs[petID, default: []].contains(item.id) },
                            set: { model.setItemIncludedInNextRequest(item.id, petID: petID, included: $0) }
                        ))
                    }
                }
                Text("请求固定使用 store: false，不会读取屏幕、代码或其他宠物数据。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(22).frame(width: 360)
        }
    }

    private func bubble(_ line: ChatLine) -> some View {
        HStack {
            if line.role == .user { Spacer(minLength: 30) }
            VStack(alignment: line.role == .user ? .trailing : .leading, spacing: 5) {
                Text(ChatMarkdownRenderer.attributed(line.text.isEmpty ? "……" : line.text))
                    .textSelection(.enabled)
                if let correction = model.correctionText(for: line.id), !correction.isEmpty {
                    DisclosureGroup("一个小调整") {
                        Text(ChatMarkdownRenderer.attributed(correction)).font(.caption).foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                }
                if !line.text.isEmpty {
                    HStack(spacing: 8) {
                        if line.role == .user && line.id == model.chatLines[petID]?.last(where: { $0.role == .user })?.id {
                            Button("编辑并重发") {
                                _ = model.editLastUserMessage(for: petID)
                                isEditing = true
                            }
                        }
                        Button(line.isFavorite ? "已收藏" : "收藏") {
                            if line.isFavorite { return }
                            favoriteLine = line
                        }
                    }
                    .buttonStyle(.plain).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(line.role == .user ? theme.userBubble : theme.petBubble, in: RoundedRectangle(cornerRadius: line.role == .user ? 19 : 14, style: .continuous))
            if line.role == .assistant { Spacer(minLength: 30) }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(theme.placeholder, text: Binding(
                get: { model.chatDrafts[petID, default: ""] },
                set: { model.chatDrafts[petID] = $0 }
            ), axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .onSubmit { model.sendChat(to: petID) }
            if model.isChatting.contains(petID) {
                Button { model.stopChat(for: petID) } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("停止生成")
            } else {
                Button { model.sendChat(to: petID) } label: { Image(systemName: "arrow.up.circle.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.chatDrafts[petID, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(isEditing ? "重发" : "发送")
            }
        }
        .padding(12)
    }
}

private struct FavoriteChatEditor: View {
    @EnvironmentObject private var model: AppModel
    let line: ChatLine
    let petID: PetID
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var translation = ""
    @State private var tags = "自然表达"

    init(line: ChatLine, petID: PetID) {
        self.line = line; self.petID = petID; _title = State(initialValue: String(line.text.prefix(40)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("收藏这句话").font(.headline)
            TextField("标题", text: $title).textFieldStyle(.roundedBorder)
            Text(ChatMarkdownRenderer.attributed(line.text)).textSelection(.enabled)
            TextField("中文翻译（可选）", text: $translation).textFieldStyle(.roundedBorder)
            TextField("标签", text: $tags).textFieldStyle(.roundedBorder)
            HStack { Button("取消") { dismiss() }; Spacer(); Button("保存") {
                let parsedTags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                model.favoriteChatLine(line, petID: petID, title: title, translation: translation, tags: parsedTags)
                dismiss()
            }.buttonStyle(.borderedProminent) }
        }
        .padding(22).frame(width: 390)
    }
}
