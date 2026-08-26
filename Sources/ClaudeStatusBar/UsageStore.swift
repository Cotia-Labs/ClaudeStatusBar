import AppKit
import Combine

/// Single source of truth for the UI: polls usage + service status and
/// publishes the latest snapshot.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var usage: UsageSnapshot?
    @Published private(set) var usageError: String?
    @Published private(set) var status: StatusSummary?
    @Published private(set) var lastUpdate: Date?
    /// When the numbers on screen were actually fetched, as opposed to the
    /// last attempt. Drives the "dados de …" note when a refresh fails.
    @Published private(set) var lastGoodUpdate: Date?
    @Published private(set) var isRefreshing = false
    /// Release mais recente do GitHub, quando é mais nova que a instalada.
    @Published private(set) var availableUpdate: Release?

    /// Shortest gap between two calls to the usage endpoint.
    private static let minimumSpacing: TimeInterval = 60
    private static let maximumBackoff: TimeInterval = 900

    private var nextAllowedFetch: Date?
    private var backoff: TimeInterval?

    private let usageFetcher = UsageFetcher()
    private let statusFetcher = StatusFetcher()
    private let notifier = Notifier()
    private let updateChecker = UpdateChecker()
    private var timer: Timer?
    private var updateTimer: Timer?
    private var notifiedThresholds: Set<Int> = []
    private var lastWindowReset: Date?

    /// Utilization of the current session window, 0...1. Drives the gauge.
    var sessionFraction: Double { usage?.session?.fraction ?? 0 }

    var level: UsageLevel { UsageLevel(fraction: sessionFraction) }

    func start() {
        notifier.requestAuthorizationIfNeeded()
        refresh()
        rescheduleTimer()

        checkForUpdates()
        // Uma vez por dia basta: o repositório é público, mas a API anônima do
        // GitHub dá 60 chamadas por hora por IP.
        updateTimer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdates() }
        }
        updateTimer?.tolerance = 3600
    }

    /// Consulta a última release. A checagem automática é silenciosa quando
    /// falha (offline, limite da API); `manual` avisa o resultado de qualquer
    /// jeito, inclusive quando já se está na versão mais nova.
    func checkForUpdates(manual: Bool = false) {
        guard manual || Preferences.checkForUpdates else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let checker = self.updateChecker
            guard let release = try? await checker.latest() else {
                if manual {
                    self.notifier.notify(title: "Não foi possível verificar atualizações",
                                         body: "Tente de novo em alguns minutos.")
                }
                return
            }

            guard isVersion(release.version, newerThan: AppInfo.version) else {
                self.availableUpdate = nil
                if manual {
                    self.notifier.notify(title: "\(AppInfo.displayName) está atualizado",
                                         body: "Você já está na versão \(AppInfo.version).")
                }
                return
            }

            self.availableUpdate = release
            // Sem isto, a mesma release voltaria a avisar a cada checagem.
            guard manual || Preferences.lastNotifiedVersion != release.version else { return }
            Preferences.lastNotifiedVersion = release.version
            self.notifier.notify(title: "Nova versão \(release.version) disponível",
                                 body: "Você tem a \(AppInfo.version). Clique para baixar o DMG.",
                                 link: release.htmlURL)
        }
    }

    func rescheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Preferences.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 5
    }

    /// Refreshes, unless a call is in flight or we are inside the cooldown.
    /// Opening the popover calls this on every open, so the cooldown is what
    /// keeps the usage endpoint from throttling us.
    func refresh(force: Bool = false) {
        guard !isRefreshing else { return }
        // A manual refresh skips the plain cooldown, but never a 429 backoff.
        let respectsCooldown = !force || backoff != nil
        if respectsCooldown, let earliest = nextAllowedFetch, Date() < earliest { return }
        isRefreshing = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Bound to locals first: Swift 5.10 rejects `async let` reading
            // captured properties directly from concurrent code.
            let fetcher = self.statusFetcher
            async let usageResult = self.fetchUsage()
            async let statusResult = try? fetcher.fetch()

            switch await usageResult {
            case .success(let snapshot):
                usageError = nil
                backoff = nil
                nextAllowedFetch = Date().addingTimeInterval(Self.minimumSpacing)
                handleThresholds(snapshot)
                usage = snapshot
                lastGoodUpdate = Date()
            case .failure(let error):
                usageError = error.localizedDescription
                applyBackoff(for: error)
            }
            status = await statusResult
            lastUpdate = Date()
            isRefreshing = false
        }
    }

    /// Honors `Retry-After` when present, otherwise doubles the wait up to
    /// 15 minutes so a throttled account stops hammering the endpoint.
    private func applyBackoff(for error: Error) {
        var wait = Self.minimumSpacing
        if case UsageFetcher.FetchError.throttled(let retryAfter) = error {
            wait = retryAfter ?? min((backoff ?? Self.minimumSpacing) * 2, Self.maximumBackoff)
        }
        backoff = wait
        nextAllowedFetch = Date().addingTimeInterval(wait)
    }

    private func fetchUsage() async -> Result<UsageSnapshot, Error> {
        do { return .success(try await usageFetcher.fetch()) } catch { return .failure(error) }
    }

    /// Notifies once per threshold crossing, rearming when the window resets.
    private func handleThresholds(_ snapshot: UsageSnapshot) {
        guard let window = snapshot.mostConstrained else { return }
        if window.resetsAt != lastWindowReset {
            lastWindowReset = window.resetsAt
            notifiedThresholds.removeAll()
        }
        guard Preferences.notifyOnChange else { return }

        for threshold in [80, 95] where Int(window.utilization) >= threshold
            && !notifiedThresholds.contains(threshold) {
            notifiedThresholds.insert(threshold)
            notifier.notify(
                title: "Uso do Claude em \(Int(window.utilization))%",
                body: window.resetsAt.map { "Reinicia \(Formatters.absolute(from: $0))" } ?? "Limite do plano"
            )
        }
    }
}

enum Formatters {
    /// "2 h 46 min" — the countdown shown next to an open window.
    static func countdown(to date: Date, now: Date = Date()) -> String {
        let remaining = max(0, date.timeIntervalSince(now))
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        if minutes > 0 { return "\(minutes) min \(seconds) s" }
        return "\(seconds) s"
    }

    /// "sáb., 11:00" for resets further out than today.
    static func absolute(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.setLocalizedDateFormatFromTemplate(
            Calendar.current.isDateInToday(date) ? "HH:mm" : "EEE, HH:mm"
        )
        return formatter.string(from: date)
    }
}
