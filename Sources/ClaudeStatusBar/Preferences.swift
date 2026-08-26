import AppKit
import Foundation

/// How the gauge draws itself in the menu bar.
enum MenuBarStyle: String, CaseIterable {
    /// The filling ring (default).
    case ring
    /// Ring plus the percentage in text.
    case ringPercent
    /// Percentage only, no ring — the narrowest option that still shows a number.
    case percent
    /// A single colored dot: the quietest way to keep the icon reachable.
    case dot

    var title: String {
        switch self {
        case .ring: return L("Ring")
        case .ringPercent: return L("Ring + percentage")
        case .percent: return L("Percentage only")
        case .dot: return L("Dot")
        }
    }
}

/// User-tunable settings, persisted in UserDefaults.
enum Preferences {
    private static let refreshKey = "refreshInterval"
    private static let notifyKey = "notifyOnChange"
    private static let showTextKey = "showTextInMenuBar"
    private static let styleKey = "menuBarStyle"
    private static let discreetKey = "discreetBelowPercent"
    private static let checkUpdatesKey = "checkForUpdates"
    private static let notifiedVersionKey = "lastNotifiedVersion"

    /// The usage endpoint throttles aggressively, so a minute is the floor.
    static let refreshChoices: [TimeInterval] = [60, 300, 900, 1800]

    /// 0 disables the quiet mode; otherwise the gauge shrinks to a dim dot
    /// while the session sits below this percentage.
    static let discreetChoices: [Int] = [0, 25, 50, 75]

    static var refreshInterval: TimeInterval {
        get {
            let stored = UserDefaults.standard.double(forKey: refreshKey)
            return refreshChoices.contains(stored) ? stored : 300
        }
        set { UserDefaults.standard.set(newValue, forKey: refreshKey) }
    }

    static var notifyOnChange: Bool {
        get { UserDefaults.standard.object(forKey: notifyKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: notifyKey) }
    }

    /// Reads the pre-1.0.9 boolean once, so upgrading keeps the chosen look.
    static var menuBarStyle: MenuBarStyle {
        get {
            if let raw = UserDefaults.standard.string(forKey: styleKey),
               let style = MenuBarStyle(rawValue: raw) {
                return style
            }
            let legacyText = UserDefaults.standard.object(forKey: showTextKey) as? Bool ?? false
            return legacyText ? .ringPercent : .ring
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: styleKey) }
    }

    static var discreetBelowPercent: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: discreetKey)
            return discreetChoices.contains(stored) ? stored : 0
        }
        set { UserDefaults.standard.set(newValue, forKey: discreetKey) }
    }

    static var checkForUpdates: Bool {
        get { UserDefaults.standard.object(forKey: checkUpdatesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: checkUpdatesKey) }
    }

    /// Última versão já anunciada, para não avisar da mesma release todo dia.
    static var lastNotifiedVersion: String? {
        get { UserDefaults.standard.string(forKey: notifiedVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: notifiedVersionKey) }
    }

    /// Follows the system setting; when on, the gauge snaps instead of easing,
    /// stops pulsing, and the panel drops its spring animations.
    @MainActor
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
