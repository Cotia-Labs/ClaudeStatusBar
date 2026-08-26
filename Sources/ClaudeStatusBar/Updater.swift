import AppKit
import Sparkle

/// Sparkle front-end: checks the appcast, downloads the DMG and installs it in
/// place, replacing the old "download the DMG and drag it yourself" flow.
///
/// Everything is optional at runtime. Sparkle needs a real app bundle carrying
/// `SUFeedURL` and `SUPublicEDKey`, so `swift run` and the ad-hoc builds made
/// before the signing key exists simply get `isAvailable == false`, and the
/// caller falls back to the GitHub releases check.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    /// Called with the version string when the appcast advertises a newer
    /// build, so the panel can show its banner.
    var onUpdateFound: ((String) -> Void)?

    private var controller: SPUStandardUpdaterController?

    var isAvailable: Bool { controller != nil }

    override init() {
        super.init()
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        // `startingUpdater: true` schedules the background check itself; the
        // standard user driver owns the "new version available" window.
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: self,
                                                  userDriverDelegate: nil)
        applyPreference()
    }

    /// Mirrors the "Check for updates automatically" toggle onto Sparkle.
    func applyPreference() {
        controller?.updater.automaticallyChecksForUpdates = Preferences.checkForUpdates
    }

    /// Explicit check: Sparkle reports "you're up to date" on its own.
    func checkNow() {
        controller?.updater.checkForUpdates()
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in self.onUpdateFound?(version) }
    }
}
