import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var gauge: MenuBarGauge!
    private var popover: NSPopover!
    private let store = UsageStore()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        gauge = MenuBarGauge()
        gauge.onFrame = { [weak self] image in
            self?.statusItem.button?.image = image
            self?.statusItem.length = image.size.width
        }

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let controller = NSHostingController(
            rootView: UsagePanel(store: store,
                                 onRefresh: { [weak self] in self?.store.refresh(force: true) },
                                 onOpenMenu: { [weak self] view in self?.showMenu(anchoredTo: view) },
                                 onUpdate: { [weak self] in self?.store.actOnUpdate() })
        )
        // Let the controller report the SwiftUI size, and seed the popover with
        // it: left at the default 320x320, AppKit positions the panel for that
        // size and it ends up floating well below the menu bar.
        controller.sizingOptions = [.preferredContentSize]

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = controller
        popover.contentSize = controller.view.fittingSize

        observeStore()
        store.start()
    }

    private func observeStore() {
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.renderGauge() }
            .store(in: &cancellables)
        renderGauge()
    }

    private func renderGauge() {
        gauge.update(fraction: store.sessionFraction,
                     level: store.level,
                     stale: store.usageError != nil)
        statusItem.button?.toolTip = tooltip
    }

    private var tooltip: String {
        if let error = store.usageError { return error }
        guard let window = store.usage?.session else { return L("Checking Claude usage…") }
        let percent = L("Current session: %d%% used", Int(window.utilization.rounded()))
        guard let resetsAt = window.resetsAt else { return percent }
        return L("%1$@ · resets in %2$@", percent, Formatters.countdown(to: resetsAt))
    }

    // MARK: - Interaction

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isSecondary {
            showMenu(anchoredTo: sender)
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.refresh()
            // The panel grows and shrinks (error box, extra windows), so the
            // size has to be current before AppKit places it.
            if let controller = popover.contentViewController {
                controller.view.layoutSubtreeIfNeeded()
                popover.contentSize = controller.view.fittingSize
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showMenu(anchoredTo view: NSView) {
        let menu = NSMenu()

        let versionItem = NSMenuItem(title: "\(AppInfo.displayName) \(AppInfo.versionLabel)",
                                     action: nil,
                                     keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let publisherItem = NSMenuItem(title: AppInfo.signature,
                                       action: #selector(openPublisher),
                                       keyEquivalent: "")
        publisherItem.target = self
        menu.addItem(publisherItem)
        menu.addItem(.separator())

        menu.addItem(submenu(L("Update interval"),
                             options: Preferences.refreshChoices,
                             current: Preferences.refreshInterval,
                             title: describe(interval:),
                             action: #selector(setInterval(_:))))

        menu.addItem(submenu(L("Menu bar"),
                             options: MenuBarStyle.allCases,
                             current: Preferences.menuBarStyle,
                             title: \.title,
                             action: #selector(setMenuBarStyle(_:))))

        menu.addItem(submenu(L("Discreet below"),
                             options: Preferences.discreetChoices,
                             current: Preferences.discreetBelowPercent,
                             title: describe(discreet:),
                             action: #selector(setDiscreet(_:))))

        menu.addItem(toggle(L("Warn at 80% and 95%"),
                            #selector(toggleNotify),
                            on: Preferences.notifyOnChange))
        menu.addItem(toggle(L("Check for updates automatically"),
                            #selector(toggleUpdateCheck),
                            on: Preferences.checkForUpdates))
        menu.addItem(toggle(L("Open at login"),
                            #selector(toggleLaunchAtLogin),
                            on: SMAppService.mainApp.status == .enabled))

        menu.addItem(.separator())
        let updateItem = NSMenuItem(
            title: store.availableUpdate.map { L("Download version %@", $0.version) }
                ?? L("Check for updates…"),
            action: #selector(checkForUpdates),
            keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        let statusItemEntry = NSMenuItem(title: L("Open status.anthropic.com"),
                                         action: #selector(openStatusPage),
                                         keyEquivalent: "")
        statusItemEntry.target = self
        menu.addItem(statusItemEntry)

        let licenseItem = NSMenuItem(title: L("License: noncommercial use"),
                                     action: #selector(openLicense),
                                     keyEquivalent: "")
        licenseItem.target = self
        menu.addItem(licenseItem)

        let quit = NSMenuItem(title: L("Quit"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(.separator())
        menu.addItem(quit)

        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: view.bounds.height + 4),
                   in: view)
    }

    /// One checkmarked submenu per setting; the chosen value rides along in
    /// `representedObject` so the action just reads it back.
    private func submenu<Value: Equatable>(_ title: String,
                                           options: [Value],
                                           current: Value,
                                           title itemTitle: (Value) -> String,
                                           action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let child = NSMenu()
        for option in options {
            let item = NSMenuItem(title: itemTitle(option), action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = option == current ? .on : .off
            child.addItem(item)
        }
        parent.submenu = child
        return parent
    }

    private func toggle(_ title: String, _ selector: Selector, on: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    private func describe(interval: TimeInterval) -> String {
        if interval < 60 { return L("%d seconds", Int(interval)) }
        let minutes = Int(interval / 60)
        return minutes == 1 ? L("1 minute") : L("%d minutes", minutes)
    }

    private func describe(discreet percent: Int) -> String {
        percent == 0 ? L("Off") : "\(percent)%"
    }

    // MARK: - Actions

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        Preferences.refreshInterval = interval
        store.rescheduleTimer()
    }

    @objc private func setMenuBarStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? MenuBarStyle else { return }
        Preferences.menuBarStyle = style
        renderGauge()
    }

    @objc private func setDiscreet(_ sender: NSMenuItem) {
        guard let percent = sender.representedObject as? Int else { return }
        Preferences.discreetBelowPercent = percent
        renderGauge()
    }

    @objc private func toggleUpdateCheck() {
        Preferences.checkForUpdates.toggle()
        store.applyUpdatePreference()
    }

    /// Se já sabemos de uma versão nova, o item vira o atalho de download.
    @objc private func checkForUpdates() {
        store.actOnUpdate()
    }

    @objc private func toggleNotify() {
        Preferences.notifyOnChange.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = L("Could not change the open-at-login setting")
            alert.runModal()
        }
    }

    @objc private func openPublisher() {
        NSWorkspace.shared.open(AppInfo.publisherURL)
    }

    @objc private func openLicense() {
        NSWorkspace.shared.open(
            URL(string: "https://github.com/Cotia-Labs/ClaudeStatusBar/blob/main/LICENSE.md")!
        )
    }

    @objc private func openStatusPage() {
        NSWorkspace.shared.open(URL(string: "https://status.anthropic.com")!)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
