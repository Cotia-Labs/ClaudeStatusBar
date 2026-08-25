import Foundation

/// Bundle metadata surfaced in the UI. Falls back to the VERSION baked into
/// the source when running the bare executable (`swift run`), which has no
/// Info.plist to read.
enum AppInfo {
    static let fallbackVersion = "1.0.4"

    static var displayName: String {
        bundleString("CFBundleDisplayName") ?? bundleString("CFBundleName") ?? "Claude Status"
    }

    static var version: String {
        bundleString("CFBundleShortVersionString") ?? fallbackVersion
    }

    static var build: String? {
        bundleString("CFBundleVersion")
    }

    /// "v1.0.3" — with the build number appended when it is not the local `1`.
    static var versionLabel: String {
        guard let build, build != "1" else { return "v\(version)" }
        return "v\(version) (\(build))"
    }

    private static func bundleString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else { return nil }
        return value
    }
}
