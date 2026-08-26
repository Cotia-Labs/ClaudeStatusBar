import Foundation

/// User-tunable settings, persisted in UserDefaults.
enum Preferences {
    private static let refreshKey = "refreshInterval"
    private static let notifyKey = "notifyOnChange"
    private static let showTextKey = "showTextInMenuBar"
    private static let checkUpdatesKey = "checkForUpdates"
    private static let notifiedVersionKey = "lastNotifiedVersion"

    /// The usage endpoint throttles aggressively, so a minute is the floor.
    static let refreshChoices: [TimeInterval] = [60, 300, 900, 1800]

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

    static var showTextInMenuBar: Bool {
        get { UserDefaults.standard.object(forKey: showTextKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: showTextKey) }
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
}
