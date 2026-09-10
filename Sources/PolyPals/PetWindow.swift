import AppKit
import CoreGraphics
import QuartzCore
import SpriteKit
import SwiftUI

@MainActor
final class PetWindowManager {
    private let model: AppModel
    private var controllers: [PetID: PetWindowController] = [:]
    private var welcomeController: NSWindowController?
    private var screenObserver: NSObjectProtocol?
    private var perchedPetID: PetID?

    init(model: AppModel) {
        self.model = model
        for pet in PetID.allCases {
            controllers[pet] = PetWindowController(petID: pet, model: model)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.controllers.values.forEach { $0.reconcileWithVisibleScreens() } }
        }
    }

    func showAll() {
        for pet in PetID.allCases { refresh(pet) }
    }

    func refresh(_ petID: PetID) {
        guard let controller = controllers[petID] else { return }
        let profile = model.profile(for: petID)
        controller.updateProfile()
        if profile.isVisible && !profile.isSleeping && !model.presentationMode {
            controller.show()
        } else {
            controller.hide()
        }
    }

    func openDetail(_ petID: PetID, tab: Int = 0) {
        beginFocusedInteraction(with: petID)
        model.requestedTab[petID] = tab
        controllers[petID]?.openDetail()
    }

    func openChat(_ petID: PetID) {
        beginFocusedInteraction(with: petID)
        controllers[petID]?.openChatPanel()
    }

    func beginFocusedInteraction(with petID: PetID) {
        for (otherID, controller) in controllers where otherID != petID {
            controller.closeInteractionWindows()
            controller.lowerBehindFocusedInteraction()
        }
        controllers[petID]?.show()
    }

    func endFocusedInteraction(for petID: PetID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.controllers[petID]?.hasOpenInteractionWindow != true else { return }
            for id in PetID.allCases { self.refresh(id) }
        }
    }

    func closeDetailAndReturn(_ petID: PetID) {
        controllers[petID]?.closeDetailAndReturn()
    }

    func wave(_ petID: PetID) {
        controllers[petID]?.show()
        controllers[petID]?.play(.waving)
    }

    func play(_ state: AnimationState, for petID: PetID) {
        controllers[petID]?.play(state)
    }

    func playRelationshipLevelUp(_ petID: PetID) {
        controllers[petID]?.show()
        controllers[petID]?.playBehavior(.celebrate, duration: 2.2)
    }

    func celebrate(_ petID: PetID) {
        controllers[petID]?.show()
        controllers[petID]?.playBehavior(.celebrate, duration: 2.2)
    }

    func reservePerch(for petID: PetID) -> Bool {
        guard perchedPetID == nil || perchedPetID == petID else { return false }
        perchedPetID = petID
        return true
    }

    func releasePerch(for petID: PetID) {
        if perchedPetID == petID { perchedPetID = nil }
    }

    func cancelAmbientBehaviors() {
        controllers.values.forEach { $0.cancelAmbientBehavior(restoreHome: true) }
        perchedPetID = nil
    }

    func invite(_ candidate: InvitationCandidate) {
        controllers[candidate.petID]?.showInvitation(candidate)
    }

    func dismissInvitation(_ petID: PetID) {
        controllers[petID]?.dismissInvitation()
    }

    func dismissAllInvitations() {
        controllers.values.forEach { $0.dismissInvitation() }
    }

    func setPetsHidden(_ hidden: Bool) {
        if hidden {
            controllers.values.forEach { $0.hide() }
        } else {
            showAll()
        }
    }

    func showWelcome() {
        if let window = welcomeController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = WelcomeView().environmentObject(model)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "欢迎来到 PolyPals"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 620, height: 500))
        window.center()
        welcomeController = NSWindowController(window: window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class NonActivatingPetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PetWindowController: NSObject {
    let petID: PetID
    private let model: AppModel
    private let panel: NonActivatingPetPanel
    private let spriteView: PetSpriteView
    private var detailController: NSWindowController?
    private var chatController: PetChatPanelController?
    private var invitationPanel: NonActivatingPetPanel?
    private var returnApplication: NSRunningApplication?
    private var idleLifeTimer: Timer?
    private var lastDirectInteraction = Date()
    private var ambientReturnWorkItem: DispatchWorkItem?
    private var perchFollowTimer: Timer?
    private var pointerTimer: Timer?
    private var lastPointerPoint = NSPoint.zero
    private var lastPointerUpdate = Date.distantPast
    private let ambientEngine = AmbientBehaviorEngine()
    private let windowProvider: any WindowEdgeProviding = SystemWindowEdgeProvider()
    private let perchSelector = PerchTargetSelector()
    private var behaviorMachine = PetBehaviorStateMachine()
    private var activePerchTarget: PerchTarget?
    private var homeOrigin: NSPoint?

    init(petID: PetID, model: AppModel) {
        self.petID = petID
        self.model = model
        let size = model.profile(for: petID).size
        panel = NonActivatingPetPanel(
            contentRect: NSRect(x: 100, y: 100, width: size, height: size * 1.08),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        spriteView = PetSpriteView(frame: panel.contentView?.bounds ?? .zero, petID: petID)
        super.init()
        spriteView.owner = self
        panel.contentView = spriteView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = collectionBehavior()
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        restorePosition()
        idleLifeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.performIdleLifeIfAppropriate() }
        }
    }

    func show() {
        spriteView.isPaused = false
        panel.orderFrontRegardless()
    }

    var hasOpenInteractionWindow: Bool {
        detailController?.window?.isVisible == true || chatController?.window?.isVisible == true
    }

    func closeInteractionWindows() {
        chatController?.close()
        chatController = nil
        detailController?.window?.close()
        detailController = nil
        dismissInvitation()
    }

    func lowerBehindFocusedInteraction() {
        panel.orderBack(nil)
    }

    func hide() {
        cancelAmbientBehavior(restoreHome: true)
        panel.orderOut(nil)
        spriteView.isPaused = true
    }

    func updateProfile() {
        let profile = model.profile(for: petID)
        let frame = panel.frame
        panel.setFrame(NSRect(x: frame.minX, y: frame.minY, width: profile.size, height: profile.size * 1.08), display: true)
        spriteView.frame = panel.contentView?.bounds ?? .zero
        panel.collectionBehavior = collectionBehavior()
    }

    func play(_ state: AnimationState) {
        spriteView.sceneModel.play(state)
    }

    func playBehavior(_ animation: PetBehaviorAnimation, duration: TimeInterval) {
        cancelScheduledAmbientReturn()
        if !behaviorMachine.perform(animation) {
            cancelAmbientBehavior(restoreHome: true)
            guard behaviorMachine.perform(animation) else { return }
        }
        spriteView.sceneModel.playBehavior(animation, returnToIdleAfter: nil)
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.behaviorMachine.finish()
                self?.play(.idle)
            }
        }
        ambientReturnWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    private func playAmbient(_ state: AnimationState, duration: TimeInterval) {
        ambientReturnWorkItem?.cancel()
        spriteView.sceneModel.play(state, returnToIdleAfter: nil)
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.play(.idle) }
        }
        ambientReturnWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    func openDetail() {
        // The card/detail panel and the compact chat are mutually exclusive.
        // Opening a package must never resurrect or retain the chat panel.
        chatController?.close()
        chatController = nil
        model.windowManager?.beginFocusedInteraction(with: petID)
        registerDirectInteraction()
        model.markInteraction(with: petID)
        play(.waiting)
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            returnApplication = frontmost
        }
        if let window = detailController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = PetDetailView(petID: petID).environmentObject(model)
        let window = NSPanel(contentViewController: NSHostingController(rootView: root))
        window.title = PetDefinition.definition(for: petID).name
        window.styleMask = [.titled, .closable, .resizable, .utilityWindow]
        window.setContentSize(NSSize(width: 760, height: 620))
        window.minSize = NSSize(width: 620, height: 480)
        window.center()
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        detailController = NSWindowController(window: window)
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openChatPanel() {
        detailController?.window?.close()
        detailController = nil
        model.windowManager?.beginFocusedInteraction(with: petID)
        registerDirectInteraction()
        model.markInteraction(with: petID)
        if let chatController {
            chatController.show()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = PetChatPanelController(
            petID: petID,
            model: model,
            ownerPanel: panel,
            onClose: { [weak self] in
                guard let self else { return }
                self.chatController = nil
                self.model.windowManager?.endFocusedInteraction(for: self.petID)
            }
        )
        chatController = controller
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeDetailAndReturn() {
        detailController?.window?.close()
        returnApplication?.activate(options: [])
        returnApplication = nil
    }

    func showInvitation(_ candidate: InvitationCandidate) {
        show()
        play(.waving)
        dismissInvitation()
        let view = InvitationBubbleView(
            candidate: candidate,
            accept: { [weak self] in self?.model.acceptInvitation(for: candidate.petID) },
            decline: { [weak self] in self?.model.declineInvitation(for: candidate.petID) },
            snoozeHour: { [weak self] in self?.model.snoozeInvitationOneHour(for: candidate.petID) },
            skipToday: { [weak self] in self?.model.skipInvitationToday(for: candidate.petID) },
            quietHour: { [weak self] in self?.model.quietForOneHour() }
        )
        let invitation = NonActivatingPetPanel(
            contentRect: NSRect(x: panel.frame.midX - 150, y: panel.frame.maxY + 8, width: 300, height: 118),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        invitation.contentViewController = NSHostingController(rootView: view)
        invitation.isOpaque = false
        invitation.backgroundColor = .clear
        invitation.hasShadow = true
        invitation.level = .floating
        invitation.collectionBehavior = panel.collectionBehavior
        invitation.becomesKeyOnlyIfNeeded = true
        invitationPanel = invitation
        invitation.orderFrontRegardless()
    }

    func dismissInvitation() {
        invitationPanel?.orderOut(nil)
        invitationPanel = nil
    }

    func showQuickMenu(event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        menu.addItem(item("聊一下", action: #selector(openChat)))
        menu.addItem(item("给我一个小套餐", action: #selector(openCards)))
        menu.addItem(item("看看它带回了什么", action: #selector(openBackpack)))
        menu.addItem(item("送它一个东西", action: #selector(giveGift)))
        menu.addItem(item("设置提醒", action: #selector(openPlans)))
        menu.addItem(.separator())
        menu.addItem(item("今天安静", action: #selector(quietToday)))
        menu.popUp(positioning: nil, at: view.convert(event.locationInWindow, from: nil), in: view)
    }

    func showContextMenu(event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        menu.addItem(item("休眠", action: #selector(sleep)))
        menu.addItem(item("恢复默认位置", action: #selector(resetPosition)))
        menu.addItem(item("缩小", action: #selector(makeSmaller)))
        menu.addItem(item("放大", action: #selector(makeLarger)))
        menu.addItem(.separator())
        menu.addItem(item("仅手动", action: #selector(modeManual)))
        menu.addItem(item("自然停顿", action: #selector(modeNatural)))
        menu.addItem(item("偶尔邀请", action: #selector(modeOccasional)))
        menu.addItem(.separator())
        menu.addItem(item("打开角色设置", action: #selector(openCharacter)))
        menu.addItem(item("暂时隐藏", action: #selector(hidePet)))
        menu.popUp(positioning: nil, at: view.convert(event.locationInWindow, from: nil), in: view)
    }

    func didFinishDragging(from oldOrigin: NSPoint) {
        registerDirectInteraction()
        if oldOrigin != panel.frame.origin {
            snapToEdge()
            persistPosition()
            play(panel.frame.origin.x >= oldOrigin.x ? .runningRight : .runningLeft)
        }
        chatController?.reposition()
    }

    func registerDirectInteraction() {
        lastDirectInteraction = Date()
        cancelAmbientBehavior(restoreHome: false)
        play(.idle)
        panel.contentView?.layer?.removeAllAnimations()
    }

    func cancelAmbientBehavior(restoreHome: Bool) {
        cancelScheduledAmbientReturn()
        perchFollowTimer?.invalidate()
        perchFollowTimer = nil
        pointerTimer?.invalidate()
        pointerTimer = nil
        panel.contentView?.layer?.removeAllAnimations()
        behaviorMachine.cancel()
        activePerchTarget = nil
        model.windowManager?.releasePerch(for: petID)
        if restoreHome, let homeOrigin {
            panel.setFrameOrigin(homeOrigin)
        }
        homeOrigin = nil
    }

    private func cancelScheduledAmbientReturn() {
        ambientReturnWorkItem?.cancel()
        ambientReturnWorkItem = nil
    }

    private func performIdleLifeIfAppropriate(now: Date = Date()) {
        let profile = model.profile(for: petID)
        guard panel.isVisible, !profile.isSleeping, !model.presentationMode,
              ProactiveMode(rawValue: profile.proactiveMode) != .manual,
              detailController?.window?.isVisible != true,
              invitationPanel?.isVisible != true,
              now.timeIntervalSince(lastDirectInteraction) >= 45,
              let screen = panel.screen ?? NSScreen.main else { return }
        let routine = model.routineState(for: petID)
        guard routine.lastAmbientActionAt.map({ now.timeIntervalSince($0) >= ambientEngine.minimumActionInterval }) ?? true else { return }
        let ambientItem = model.ambientInventoryItem(for: petID, at: now)
        let recentActions = (try? JSONDecoder().decode([AmbientAction].self, from: routine.recentActionsJSON)) ?? []
        let context = PetActivityContext(
            petID: petID,
            now: now,
            hour: Calendar.current.component(.hour, from: now),
            lastInteractionAt: max(lastDirectInteraction, profile.lastInteractionAt ?? .distantPast),
            focusActive: model.focusTimer.isRunning,
            presentationMode: model.presentationMode,
            detailPanelOpen: detailController?.window?.isVisible == true,
            chatPanelOpen: chatController?.window?.isVisible == true,
            isDragging: false,
            isVisible: panel.isVisible,
            isSleeping: profile.isSleeping,
            hasInventoryItem: ambientItem != nil,
            recentActions: recentActions
        )
        guard let decision = ambientEngine.decide(context: context) else { return }
        model.recordAmbientAction(decision.action, for: petID, at: now)
        switch decision.action {
        case .nap: playBehavior(.nap, duration: decision.duration)
        case .stretch: playBehavior(.stretch, duration: decision.duration)
        case .tidyItem:
            if let ambientItem { model.recordAmbientInventoryReference(ambientItem, at: now) }
            playBehavior(petID == .mousse ? .mousseGroom : personalityAction(at: now), duration: decision.duration)
        case .lookAtPointer: followPointer(duration: decision.duration)
        case .personality: playBehavior(personalityAction(at: now), duration: decision.duration)
        case .perch:
            guard model.windowPerchingEnabled else { return }
            beginPerching(duration: decision.duration, on: screen)
        case .walkToEdge: break
        case .idle: play(.idle)
        }
        guard decision.action == .walkToEdge else {
            if decision.action != .lookAtPointer { return }
            return
        }
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let day = Calendar.current.component(.day, from: now)
        let direction = ((day + (petID == .sol ? 1 : petID == .mousse ? 2 : 3)) % 2 == 0) ? 1.0 : -1.0
        let distance = CGFloat(48 + (day % 4) * 16) * direction
        let destinationX = min(visible.maxX - panel.frame.width, max(visible.minX, panel.frame.minX + distance))
        guard abs(destinationX - panel.frame.minX) > 8 else { return }
        play(destinationX > panel.frame.minX ? .runningRight : .runningLeft)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = decision.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(NSPoint(x: destinationX, y: panel.frame.minY))
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.persistPosition()
                self?.play(.idle)
            }
        }
    }

    private func personalityAction(at date: Date) -> PetBehaviorAnimation {
        let seed = Calendar.current.ordinality(of: .minute, in: .year, for: date) ?? 0
        return PetPersonalityBehavior.action(for: petID, stableSeed: seed)
    }

    private func followPointer(duration: TimeInterval) {
        cancelScheduledAmbientReturn()
        lastPointerPoint = NSEvent.mouseLocation
        lastPointerUpdate = .distantPast
        pointerTimer?.invalidate()
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let point = NSEvent.mouseLocation
                guard hypot(point.x - self.lastPointerPoint.x, point.y - self.lastPointerPoint.y) > 3,
                      Date().timeIntervalSince(self.lastPointerUpdate) >= 0.08 else { return }
                self.lastPointerPoint = point
                self.lastPointerUpdate = Date()
                self.spriteView.sceneModel.look(toward: CGPoint(
                    x: point.x - self.panel.frame.midX,
                    y: point.y - self.panel.frame.midY
                ))
            }
        }
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.pointerTimer?.invalidate()
                self?.pointerTimer = nil
                self?.behaviorMachine.finish()
                self?.play(.idle)
            }
        }
        ambientReturnWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    private func beginPerching(duration: TimeInterval, on screen: NSScreen) {
        guard model.windowManager?.reservePerch(for: petID) == true,
              behaviorMachine.beginChoosing() else { return }
        let selection = PerchSelectionContext(
            petID: petID,
            petSize: panel.frame.size,
            petFrame: panel.frame,
            screenFrame: screen.visibleFrame,
            screenID: Self.displayID(screen) ?? "unknown",
            ownPID: ProcessInfo.processInfo.processIdentifier,
            frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            reservedRanges: []
        )
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let target = perchSelector.select(
            windows: windowProvider.visibleWindows(),
            context: selection,
            desktopTop: desktopTop
        ) ?? perchSelector.screenEdgeFallback(context: selection)
        homeOrigin = panel.frame.origin
        activePerchTarget = target
        behaviorMachine.walk(to: target)
        let destination = target.anchor
        play(destination.x >= panel.frame.minX ? .runningRight : .runningLeft)
        let travel = min(4.5, max(1.0, hypot(destination.x - panel.frame.minX, destination.y - panel.frame.minY) / 240))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = travel
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(destination)
        } completionHandler: { [weak self] in
            Task { @MainActor in self?.landOnPerch(duration: duration) }
        }
    }

    private func landOnPerch(duration: TimeInterval) {
        guard activePerchTarget != nil else { return }
        behaviorMachine.reachedPerch()
        spriteView.sceneModel.playBehavior(.perchEnter, returnToIdleAfter: nil)
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.behaviorMachine.landed()
                let seed = Calendar.current.component(.minute, from: Date())
                self.spriteView.sceneModel.playBehavior(
                    PetPersonalityBehavior.perchIdle(for: self.petID, stableSeed: seed),
                    returnToIdleAfter: nil
                )
                self.startFollowingPerch()
                self.schedulePerchDeparture(after: duration)
            }
        }
        ambientReturnWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: item)
    }

    private func startFollowingPerch() {
        perchFollowTimer?.invalidate()
        perchFollowTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPerchPosition() }
        }
    }

    private func refreshPerchPosition() {
        guard let target = activePerchTarget else { return }
        guard target.kind == .applicationWindow else { return }
        guard let number = target.windowNumber,
              let raw = windowProvider.visibleWindows().first(where: { $0.windowNumber == number }),
              let screen = panel.screen ?? NSScreen.main else {
            leavePerch()
            return
        }
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let frame = PerchCoordinateConverter.appKitFrame(fromQuartz: raw.frame, desktopTop: desktopTop)
        guard frame.intersects(screen.visibleFrame) else { leavePerch(); return }
        let relativeX = target.anchor.x - target.windowFrame.minX
        let lower = max(frame.minX + perchSelector.controlButtonReserve, screen.visibleFrame.minX + perchSelector.edgePadding)
        let upper = min(
            frame.maxX - perchSelector.edgePadding - panel.frame.width,
            screen.visibleFrame.maxX - perchSelector.edgePadding - panel.frame.width
        )
        guard upper > lower else { leavePerch(); return }
        let next = NSPoint(
            x: min(upper, max(lower, frame.minX + relativeX)),
            y: frame.maxY - panel.frame.height * 0.15
        )
        guard hypot(next.x - panel.frame.minX, next.y - panel.frame.minY) > 1.5 else { return }
        panel.setFrameOrigin(next)
    }

    private func schedulePerchDeparture(after duration: TimeInterval) {
        cancelScheduledAmbientReturn()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.leavePerch() }
        }
        ambientReturnWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    private func leavePerch() {
        guard activePerchTarget != nil else { return }
        cancelScheduledAmbientReturn()
        perchFollowTimer?.invalidate()
        perchFollowTimer = nil
        behaviorMachine.beginLeaving()
        spriteView.sceneModel.playBehavior(.perchExit, returnToIdleAfter: nil)
        let destination = homeOrigin ?? panel.frame.origin
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.behaviorMachine.beginReturning()
                self.play(destination.x >= self.panel.frame.minX ? .runningRight : .runningLeft)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = min(3.5, max(0.8, hypot(
                        destination.x - self.panel.frame.minX,
                        destination.y - self.panel.frame.minY
                    ) / 260))
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.panel.animator().setFrameOrigin(destination)
                } completionHandler: { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        self.activePerchTarget = nil
                        self.homeOrigin = nil
                        self.behaviorMachine.finish()
                        self.model.windowManager?.releasePerch(for: self.petID)
                        self.play(.idle)
                    }
                }
            }
        }
        ambientReturnWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: item)
    }

    func reconcileWithVisibleScreens() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var origin = panel.frame.origin
        origin.x = min(visible.maxX - panel.frame.width, max(visible.minX, origin.x))
        origin.y = min(visible.maxY - panel.frame.height, max(visible.minY, origin.y))
        panel.setFrameOrigin(origin)
        persistPosition()
        if let invitationPanel {
            invitationPanel.setFrameOrigin(NSPoint(
                x: min(visible.maxX - invitationPanel.frame.width, max(visible.minX, panel.frame.midX - invitationPanel.frame.width / 2)),
                y: min(visible.maxY - invitationPanel.frame.height, max(visible.minY, panel.frame.maxY + 8))
            ))
        }
    }

    @objc private func openChat() { openChatPanel() }
    @objc private func openCards() { model.startPackage(for: petID); model.requestedTab[petID] = 0; openDetail() }
    @objc private func openBackpack() { model.requestedTab[petID] = 2; openDetail() }
    @objc private func openPlans() { model.requestedTab[petID] = 3; openDetail() }
    @objc private func openCharacter() { model.requestedTab[petID] = 4; openDetail() }
    @objc private func giveGift() {
        model.giveGift(to: petID)
        playBehavior(petID == .mousse ? .mousseProud : .celebrate, duration: 2.2)
    }
    @objc private func quietToday() { model.skipInvitationToday(for: petID); play(.idle) }
    @objc private func sleep() { model.profile(for: petID).isSleeping = true; try? model.container.mainContext.save(); hide() }
    @objc private func hidePet() { model.profile(for: petID).isVisible = false; try? model.container.mainContext.save(); hide() }
    @objc private func modeManual() { setMode(.manual) }
    @objc private func modeNatural() { setMode(.naturalPause) }
    @objc private func modeOccasional() { setMode(.occasionalInvite) }
    @objc private func makeSmaller() { resize(by: -16) }
    @objc private func makeLarger() { resize(by: 16) }
    @objc private func resetPosition() { placeDefault(); persistPosition() }

    private func setMode(_ mode: ProactiveMode) {
        model.profile(for: petID).proactiveMode = mode.rawValue
        try? model.container.mainContext.save()
        model.reloadProfiles()
    }

    private func resize(by delta: Double) {
        let profile = model.profile(for: petID)
        profile.size = min(192, max(80, profile.size + delta))
        try? model.container.mainContext.save()
        model.reloadProfiles()
        updateProfile()
        snapToEdge()
        persistPosition()
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func collectionBehavior() -> NSWindow.CollectionBehavior {
        let profile = model.profile(for: petID)
        var behavior: NSWindow.CollectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]
        behavior.insert(profile.appearsOnAllSpaces ? .canJoinAllSpaces : .moveToActiveSpace)
        return behavior
    }

    private func restorePosition() {
        guard let state = model.windowState(for: petID),
              let screen = screen(matching: state.displayID) ?? NSScreen.main else {
            placeDefault()
            return
        }
        let visible = screen.visibleFrame
        let maxX = max(0, visible.width - panel.frame.width)
        let maxY = max(0, visible.height - panel.frame.height)
        panel.setFrameOrigin(NSPoint(
            x: visible.minX + min(1, max(0, state.normalizedX)) * maxX,
            y: visible.minY + min(1, max(0, state.normalizedY)) * maxY
        ))
    }

    private func placeDefault() {
        let index = CGFloat(PetID.allCases.firstIndex(of: petID) ?? 0)
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 700)
        panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 24 - index * 150, y: visible.minY + 32))
    }

    private func snapToEdge() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var origin = panel.frame.origin
        let threshold: CGFloat = 24
        if abs(panel.frame.minX - visible.minX) <= threshold { origin.x = visible.minX }
        if abs(panel.frame.maxX - visible.maxX) <= threshold { origin.x = visible.maxX - panel.frame.width }
        if abs(panel.frame.minY - visible.minY) <= threshold { origin.y = visible.minY }
        if abs(panel.frame.maxY - visible.maxY) <= threshold { origin.y = visible.maxY - panel.frame.height }
        origin.x = min(visible.maxX - panel.frame.width, max(visible.minX, origin.x))
        origin.y = min(visible.maxY - panel.frame.height, max(visible.minY, origin.y))
        panel.setFrameOrigin(origin)
    }

    private func persistPosition() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let maxX = max(1, visible.width - panel.frame.width)
        let maxY = max(1, visible.height - panel.frame.height)
        model.saveWindowState(
            petID: petID,
            displayID: Self.displayID(screen),
            normalizedX: (panel.frame.minX - visible.minX) / maxX,
            normalizedY: (panel.frame.minY - visible.minY) / maxY
        )
    }

    private func screen(matching identifier: String?) -> NSScreen? {
        guard let identifier else { return nil }
        return NSScreen.screens.first(where: { Self.displayID($0) == identifier })
    }

    private static func displayID(_ screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value)) else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }
}

extension PetWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        model.discardEphemeralChat(for: petID)
        registerDirectInteraction()
        if notification.object as? NSWindow === detailController?.window {
            detailController = nil
        }
        model.windowManager?.endFocusedInteraction(for: petID)
    }
}

@MainActor
final class PetSpriteView: SKView {
    weak var owner: PetWindowController?
    let sceneModel: PetSpriteScene
    private var pointerTrackingArea: NSTrackingArea?

    init(frame frameRect: NSRect, petID: PetID) {
        sceneModel = PetSpriteScene(size: frameRect.size, petID: petID)
        super.init(frame: frameRect)
        allowsTransparency = true
        preferredFramesPerSecond = 12
        sceneModel.scaleMode = .resizeFill
        presentScene(sceneModel)
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        owner?.registerDirectInteraction()
        if event.clickCount >= 2 {
            owner?.openDetail()
            return
        }
        let old = window?.frame.origin ?? .zero
        window?.performDrag(with: event)
        let new = window?.frame.origin ?? old
        owner?.didFinishDragging(from: old)
        if hypot(new.x - old.x, new.y - old.y) < 3 { owner?.showQuickMenu(event: event, in: self) }
    }

    override func rightMouseDown(with event: NSEvent) {
        owner?.registerDirectInteraction()
        owner?.showContextMenu(event: event, in: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        sceneModel.look(toward: CGPoint(x: point.x - bounds.midX, y: point.y - bounds.midY))
    }

    override func mouseExited(with event: NSEvent) {
        sceneModel.play(.idle)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

@MainActor
final class PetSpriteScene: SKScene {
    private let petID: PetID
    private var sprite: SKSpriteNode?
    private var emoji: SKLabelNode?
    private var currentState: AnimationState = .idle
    private lazy var atlasTexture: SKTexture? = {
        guard let url = PetAssetCatalog.spritesheetURL(for: petID),
              let image = NSImage(contentsOf: url) else { return nil }
        return SKTexture(image: image)
    }()
    private lazy var behaviorManifest = PetAssetCatalog.behaviorManifest(for: petID)
    private lazy var behaviorTexture: SKTexture? = {
        guard let url = PetAssetCatalog.behaviorSpritesheetURL(for: petID),
              let image = NSImage(contentsOf: url) else { return nil }
        return SKTexture(image: image)
    }()

    init(size: CGSize, petID: PetID) {
        self.petID = petID
        super.init(size: size)
        backgroundColor = .clear
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        configureVisual()
        play(.idle)
    }

    required init?(coder aDecoder: NSCoder) { nil }

    override func didChangeSize(_ oldSize: CGSize) {
        sprite?.size = fittedSpriteSize()
        emoji?.fontSize = min(size.width, size.height) * 0.66
    }

    func play(_ state: AnimationState, returnToIdleAfter duration: TimeInterval? = 1.4) {
        currentState = state
        removeAction(forKey: "return-idle")
        if let sprite, let textures = atlasTextures(for: state), !textures.isEmpty {
            sprite.removeAllActions()
            sprite.run(.repeatForever(.animate(with: textures, timePerFrame: 0.13, resize: false, restore: true)), withKey: "frames")
        } else if let emoji {
            emoji.removeAllActions()
            let action: SKAction
            switch state {
            case .idle: action = .sequence([.scale(to: 1.02, duration: 1.1), .scale(to: 0.98, duration: 1.1)])
            case .waving: action = .sequence([.rotate(byAngle: 0.12, duration: 0.15), .rotate(byAngle: -0.24, duration: 0.2), .rotate(byAngle: 0.12, duration: 0.15)])
            case .jumping: action = .sequence([.moveBy(x: 0, y: 18, duration: 0.18), .moveBy(x: 0, y: -18, duration: 0.22)])
            case .failed: action = .sequence([.moveBy(x: -3, y: 0, duration: 0.08), .moveBy(x: 6, y: 0, duration: 0.08), .moveBy(x: -3, y: 0, duration: 0.08)])
            default: action = .sequence([.scale(to: 1.04, duration: 0.25), .scale(to: 1, duration: 0.25)])
            }
            emoji.run(state == .idle ? .repeatForever(action) : action, withKey: "fallback")
        }
        if state != .idle, let duration {
            run(.sequence([.wait(forDuration: duration), .run { [weak self] in self?.play(.idle) }]), withKey: "return-idle")
        }
    }

    func playBehavior(_ behavior: PetBehaviorAnimation, returnToIdleAfter duration: TimeInterval? = 1.8) {
        removeAction(forKey: "return-idle")
        if let sprite, let clip = behaviorManifest?.clip(behavior),
           let textures = behaviorTextures(for: clip), !textures.isEmpty {
            sprite.removeAllActions()
            let animation = SKAction.animate(
                with: textures,
                timePerFrame: clip.secondsPerFrame,
                resize: false,
                restore: !clip.loops
            )
            sprite.run(clip.loops ? .repeatForever(animation) : animation, withKey: "frames")
        } else {
            play(fallbackState(for: behavior), returnToIdleAfter: duration)
            return
        }
        if let duration {
            run(.sequence([.wait(forDuration: duration), .run { [weak self] in self?.play(.idle) }]), withKey: "return-idle")
        }
    }

    private func behaviorTextures(for clip: PetBehaviorClipManifest) -> [SKTexture]? {
        guard let texture = behaviorTexture, let manifest = behaviorManifest,
              manifest.columns > 0, !manifest.clips.isEmpty else { return nil }
        let rows = (manifest.clips.map(\.row).max() ?? -1) + 1
        guard rows > 0, clip.row >= 0, clip.row < rows,
              clip.frameCount > 0, clip.frameCount <= manifest.columns else { return nil }
        return (0..<clip.frameCount).map { column in
            let rect = CGRect(
                x: CGFloat(column) / CGFloat(manifest.columns),
                y: 1 - CGFloat(clip.row + 1) / CGFloat(rows),
                width: 1 / CGFloat(manifest.columns),
                height: 1 / CGFloat(rows)
            )
            return SKTexture(rect: rect, in: texture)
        }
    }

    private func fallbackState(for behavior: PetBehaviorAnimation) -> AnimationState {
        if let fallback = behaviorManifest?.clip(behavior)?.fallback { return fallback }
        switch behavior {
        case .celebrate, .perchEnter, .perchExit, .stretch: return .jumping
        case .perchWalkLeft: return .runningLeft
        case .perchWalkRight: return .runningRight
        case .ashInviteWing: return .waving
        case .solPouncePrep, .mousseGroom, .ashHeadTilt: return .review
        case .solEarTwitch, .mousseProud: return .waiting
        case .nap, .perchSit, .solTailChase, .solPerchTailWag, .mousseElegantSit, .ashSlowSquint: return .idle
        }
    }

    func look(toward vector: CGPoint) {
        guard hypot(vector.x, vector.y) > 6, let sprite, let texture = lookTexture(toward: vector) else { return }
        sprite.removeAllActions()
        sprite.texture = texture
    }

    private func configureVisual() {
        if let textures = atlasTextures(for: .idle), let first = textures.first {
            let node = SKSpriteNode(texture: first, size: fittedSpriteSize())
            sprite = node
            addChild(node)
        } else {
            let symbol: String = switch petID { case .sol: "🦊"; case .mousse: "🐆"; case .ash: "🦉" }
            let node = SKLabelNode(text: symbol)
            node.fontSize = min(size.width, size.height) * 0.66
            node.verticalAlignmentMode = .center
            emoji = node
            addChild(node)
        }
    }

    private func fittedSpriteSize() -> CGSize {
        let width = min(size.width, size.height * 192 / 208) * 0.95
        return CGSize(width: width, height: width * 208 / 192)
    }

    private func atlasTextures(for state: AnimationState) -> [SKTexture]? {
        guard let atlas = atlasTexture else { return nil }
        let row: Int = switch state {
        case .idle: 0
        case .runningRight: 1
        case .runningLeft: 2
        case .waving: 3
        case .jumping: 4
        case .failed: 5
        case .waiting: 6
        case .processing: 7
        case .review: 8
        }
        let count: Int = switch state {
        case .waving: 4
        case .jumping: 5
        case .idle, .waiting, .processing, .review: 6
        default: 8
        }
        return (0..<count).map { column in
            let rect = CGRect(
                x: CGFloat(column) / 8,
                y: 1 - CGFloat(row + 1) / 11,
                width: 1.0 / 8,
                height: 1.0 / 11
            )
            return SKTexture(rect: rect, in: atlas)
        }
    }


    private func lookTexture(toward vector: CGPoint) -> SKTexture? {
        guard let atlas = atlasTexture else { return nil }
        // atan2 is counter-clockwise from screen-right; convert to clockwise degrees from screen-up.
        var degrees = 90 - atan2(vector.y, vector.x) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let index = Int((degrees + 11.25) / 22.5) % 16
        let row = index < 8 ? 9 : 10
        let column = index < 8 ? index : index - 8
        let rect = CGRect(
            x: CGFloat(column) / 8,
            y: 1 - CGFloat(row + 1) / 11,
            width: 1.0 / 8,
            height: 1.0 / 11
        )
        return SKTexture(rect: rect, in: atlas)
    }
}
