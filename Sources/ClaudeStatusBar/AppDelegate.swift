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

        gauge = MenuBarGauge(frame: .zero)
        gauge.onClick = { [weak self] event in self?.handleClick(event) }
        statusItem.button?.addSubview(gauge)
        statusItem.button?.frame = gauge.frame
        statusItem.length = gauge.intrinsicContentSize.width

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: UsagePanel(store: store,
                                 onRefresh: { [weak self] in self?.store.refresh(force: true) },
                                 onOpenMenu: { [weak self] view in self?.showMenu(anchoredTo: view) })
        )

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
        gauge.update(fraction: store.headlineFraction,
                     level: store.level,
                     stale: store.usageError != nil)
        statusItem.length = gauge.intrinsicContentSize.width
        statusItem.button?.frame = gauge.frame
        statusItem.button?.toolTip = tooltip
    }

    private var tooltip: String {
        if let error = store.usageError { return error }
        guard let window = store.usage?.headline else { return "Consultando uso do Claude…" }
        let percent = "\(Int(window.utilization.rounded()))% usado"
        guard let resetsAt = window.resetsAt else { return percent }
        return "\(percent) · reinicia em \(Formatters.countdown(to: resetsAt))"
    }

    // MARK: - Interaction

    private func handleClick(_ event: NSEvent) {
        let isSecondary = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
        if isSecondary {
            showMenu(anchoredTo: gauge)
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showMenu(anchoredTo view: NSView) {
        let menu = NSMenu()

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

    @objc private func openStatusPage() {
        NSWorkspace.shared.open(URL(string: "https://status.anthropic.com")!)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
