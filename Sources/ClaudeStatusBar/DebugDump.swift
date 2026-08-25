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
                    print("\(label) \(String(format: "%5.1f", row.window.utilization))%  reinicia \(reset)")
                }
                if snapshot.rows.isEmpty { print("Nenhuma janela ativa retornada.") }
            } catch {
                print("Erro: \(error.localizedDescription)")
            }
        }
        semaphore.wait()
    }
}
