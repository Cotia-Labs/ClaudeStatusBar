import Foundation

/// One rate-limit window as reported by the OAuth usage endpoint.
struct UsageWindow: Decodable, Equatable {
    /// 0–100. The endpoint reports 0 when no window is currently open.
    let utilization: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var fraction: Double { min(max(utilization / 100, 0), 1) }
}

/// Response of `GET /api/oauth/usage`. All windows are optional because the
/// payload varies by plan (Pro, Max 5x/20x) and by which windows are open.
struct UsageSnapshot: Decodable, Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    /// The window that drives the menu bar gauge: the current session, since
    /// that is the limit that bites during a work stretch. Falls back to the
    /// weekly window on plans that report no session window.
    var session: UsageWindow? { fiveHour ?? sevenDay }

    /// Whichever window sits closest to its cap. Used for threshold warnings,
    /// so a weekly limit filling up is not missed while the session is idle.
    var mostConstrained: UsageWindow? {
        [fiveHour, sevenDay, sevenDayOpus, sevenDaySonnet]
            .compactMap { $0 }
            .max { $0.utilization < $1.utilization }
    }

    var rows: [(title: String, subtitle: String, window: UsageWindow)] {
        var result: [(String, String, UsageWindow)] = []
        if let fiveHour { result.append(("Sessão atual", "Janela de 5 horas", fiveHour)) }
        if let sevenDay { result.append(("Todos os modelos", "Semanal", sevenDay)) }
        if let sevenDayOpus { result.append(("Opus", "Semanal", sevenDayOpus)) }
        if let sevenDaySonnet { result.append(("Sonnet", "Semanal", sevenDaySonnet)) }
        return result
    }
}

enum UsageLevel {
    case comfortable, watch, tight, critical

    init(fraction: Double) {
        switch fraction {
        case ..<0.5: self = .comfortable
        case ..<0.8: self = .watch
        case ..<0.95: self = .tight
        default: self = .critical
        }
    }
}
