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
                                 onOpenMenu: { [weak self] view in self?.showMenu(anchoredTo: view) })
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
        guard let window = store.usage?.session else { return "Consultando uso do Claude…" }
        let percent = "Sessão atual: \(Int(window.utilization.rounded()))% usado"
        guard let resetsAt = window.resetsAt else { return percent }
        return "\(percent) · reinicia em \(Formatters.countdown(to: resetsAt))"
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

        let intervalItem = NSMenuItem(title: "Intervalo de atualização", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        for choice in Preferences.refreshChoices {
            let item = NSMenuItem(title: describe(interval: choice),
                                  action: #selector(setInterval(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = choice
            item.state = choice == Preferences.refreshInterval ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        menu.addItem(toggle("Mostrar porcentagem na barra",
                            #selector(toggleText),
                            on: Preferences.showTextInMenuBar))
        menu.addItem(toggle("Avisar em 80% e 95%",
                            #selector(toggleNotify),
                            on: Preferences.notifyOnChange))
        menu.addItem(toggle("Abrir no login",
                            #selector(toggleLaunchAtLogin),
                            on: SMAppService.mainApp.status == .enabled))

        menu.addItem(.separator())
        let statusItemEntry = NSMenuItem(title: "Abrir status.anthropic.com",
                                         action: #selector(openStatusPage),
                                         keyEquivalent: "")
        statusItemEntry.target = self
        menu.addItem(statusItemEntry)

        let licenseItem = NSMenuItem(title: "Licença: uso não comercial",
                                     action: #selector(openLicense),
                                     keyEquivalent: "")
        licenseItem.target = self
        menu.addItem(licenseItem)

        let quit = NSMenuItem(title: "Sair", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(.separator())
        menu.addItem(quit)

        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: view.bounds.height + 4),
                   in: view)
    }

    private func toggle(_ title: String, _ selector: Selector, on: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    private func describe(interval: TimeInterval) -> String {
        interval < 60 ? "\(Int(interval)) segundos" : "\(Int(interval / 60)) minuto\(interval >= 120 ? "s" : "")"
    }

    // MARK: - Actions

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        Preferences.refreshInterval = interval
        store.rescheduleTimer()
    }

    @objc private func toggleText() {
        Preferences.showTextInMenuBar.toggle()
        renderGauge()
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
            alert.messageText = "Não foi possível alterar a abertura no login"
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
