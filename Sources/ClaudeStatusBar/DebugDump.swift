import Foundation

/// Prints the current rate-limit windows to stdout. Never prints the token.
enum DebugDump {
    static func run() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            defer { semaphore.signal() }
            do {
                let snapshot = try await UsageFetcher().fetch()
                for row in snapshot.rows {
                    let reset = row.window.resetsAt.map { Formatters.absolute(from: $0) } ?? "—"
                    let label = row.title.padding(toLength: 18, withPad: " ", startingAt: 0)
                    print("\(label) \(String(format: "%5.1f", row.window.utilization))%  \(L("resets %@", reset))")
                }
                if snapshot.rows.isEmpty { print(L("No active window returned.")) }
            } catch {
                print(L("Error: %@", error.localizedDescription))
            }
        }
        semaphore.wait()
    }

    /// Sem UI: mostra a versão instalada, a última publicada e se há novidade.
    static func checkUpdates() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            defer { semaphore.signal() }
            do {
                let release = try await UpdateChecker().latest()
                let newer = isVersion(release.version, newerThan: AppInfo.version)
                print(L("installed: %@", AppInfo.version))
                print(L("published: %1$@ — %2$@", release.version, release.htmlURL.absoluteString))
                print(newer ? L("an update is available") : L("up to date"))
            } catch {
                print(L("could not query releases: %@", error.localizedDescription))
            }
        }
        semaphore.wait()
    }
}
