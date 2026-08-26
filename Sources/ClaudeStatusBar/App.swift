import AppKit

@main
enum ClaudeStatusBarApp {
    @MainActor
    static func main() {
        // `--dump` prints the parsed usage windows and exits: handy for
        // checking the endpoint without opening the UI.
        if CommandLine.arguments.contains("--version") {
            print("\(AppInfo.displayName) \(AppInfo.versionLabel)")
            return
        }

        if CommandLine.arguments.contains("--dump") {
            DebugDump.run()
            return
        }

        // `--check-updates` consulta a última release e imprime o veredito.
        if CommandLine.arguments.contains("--check-updates") {
            DebugDump.checkUpdates()
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.run()
    }
}
