import AppKit
import SwiftUI

@main
struct PolyPalsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            GlobalSettingsView()
                .environmentObject(AppModel.shared)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let singleInstanceLock = SingleInstanceLock(identifier: "com.polypals.PolyPals")
    private lazy var model = AppModel.shared
    private var isDuplicateLaunch = false
    private var windowManager: PetWindowManager!
    private var statusItem: NSStatusItem!
    private var settingsController: NSWindowController?
    private var proactiveCoordinator: ProactiveCoordinator?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let alreadyRunning = NSWorkspace.shared.runningApplications.contains { application in
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
                !application.isTerminated &&
                (application.bundleIdentifier == "com.polypals.PolyPals" || application.localizedName == "PolyPals")
        }
        guard !alreadyRunning, singleInstanceLock.isAcquired else {
            isDuplicateLaunch = true
            activateExistingInstance()
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isDuplicateLaunch else { return }
        NSApp.setActivationPolicy(.accessory)
        windowManager = PetWindowManager(model: model)
        model.windowManager = windowManager
        NotificationService.shared.onOpenPet = { [weak self] pet in self?.windowManager.openDetail(pet, tab: 0) }
        NotificationService.shared.onCancelSchedule = { [weak self] pet, scheduleID in
            self?.model.disableSchedule(petID: pet, scheduleID: scheduleID)
        }
        NotificationService.shared.onScheduleAction = { [weak self] pet, scheduleID, outcome in
            self?.model.recordScheduleExecution(scheduleID: scheduleID, petID: pet, outcome: outcome)
        }
        configureStatusItem()
        windowManager.showAll()
        proactiveCoordinator = ProactiveCoordinator(model: model)
        proactiveCoordinator?.start()
        if !UserDefaults.standard.bool(forKey: "completedOnboarding") { windowManager.showWelcome() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshAccessibilityStatus()
    }

    private func activateExistingInstance() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let existing = NSWorkspace.shared.runningApplications.first { application in
            application.processIdentifier != currentPID &&
                !application.isTerminated &&
                (application.bundleIdentifier == "com.polypals.PolyPals" || application.localizedName == "PolyPals")
        }
        existing?.activate(options: [.activateAllWindows])
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "PolyPals")
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        for pet in PetID.allCases {
            let item = NSMenuItem(title: "打开 \(PetDefinition.definition(for: pet).name)", action: #selector(openPet(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = pet.rawValue
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let presentation = NSMenuItem(title: model.presentationMode ? "退出演示模式" : "进入演示模式", action: #selector(togglePresentation), keyEquivalent: "")
        presentation.target = self
        menu.addItem(presentation)
        let showAll = NSMenuItem(title: "唤醒全部宠物", action: #selector(wakeAll), keyEquivalent: "")
        showAll.target = self
        menu.addItem(showAll)
        menu.addItem(.separator())
        menu.addItem(item("专注 25 分钟", action: #selector(startFocus25)))
        menu.addItem(item("专注 50 分钟", action: #selector(startFocus50)))
        if model.focusTimer.isRunning { menu.addItem(item("停止当前专注", action: #selector(stopFocus))) }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "退出 PolyPals", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func openPet(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let pet = PetID(rawValue: raw) else { return }
        windowManager.openDetail(pet)
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    @objc private func startFocus25() { model.startFocus(minutes: 25); rebuildMenu() }
    @objc private func startFocus50() { model.startFocus(minutes: 50); rebuildMenu() }
    @objc private func stopFocus() { model.stopFocus(); rebuildMenu() }

    @objc private func togglePresentation() {
        model.togglePresentationMode()
        rebuildMenu()
    }

    @objc private func wakeAll() {
        for pet in PetID.allCases {
            let profile = model.profile(for: pet)
            profile.isVisible = true
            profile.isSleeping = false
        }
        try? model.container.mainContext.save()
        model.reloadProfiles()
        windowManager.showAll()
    }

    @objc private func openSettings() {
        if let window = settingsController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = GlobalSettingsView().environmentObject(model)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "PolyPals 设置"
        window.styleMask = [.titled, .closable]
        window.center()
        settingsController = NSWindowController(window: window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}
