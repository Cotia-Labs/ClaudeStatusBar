import Foundation

/// Minimal model of the Statuspage v2 summary payload served by status.anthropic.com.
struct StatusSummary: Decodable {
    struct Page: Decodable {
        let updatedAt: Date

        enum CodingKeys: String, CodingKey { case updatedAt = "updated_at" }
    }

    struct Status: Decodable {
        let indicator: String
        let description: String
    }

    struct Component: Decodable {
        let id: String
        let name: String
        let status: String
        let group: Bool
        let showcase: Bool
    }

    struct Incident: Decodable {
        let id: String
        let name: String
        let status: String
        let impact: String
        let shortlink: URL?
        let updatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id, name, status, impact, shortlink
            case updatedAt = "updated_at"
        }
    }

    let page: Page
    let status: Status
    let components: [Component]
    let incidents: [Incident]
    let scheduledMaintenances: [Incident]

    enum CodingKeys: String, CodingKey {
        case page, status, components, incidents
        case scheduledMaintenances = "scheduled_maintenances"
    }
}

/// Severity shared by the overall indicator and by individual components.
enum Severity {
    case operational, degraded, partialOutage, majorOutage, maintenance, unknown

    /// Maps a Statuspage `status.indicator` value.
    static func fromIndicator(_ raw: String) -> Severity {
        switch raw {
        case "none": return .operational
        case "minor": return .degraded
        case "major": return .partialOutage
        case "critical": return .majorOutage
        case "maintenance": return .maintenance
        default: return .unknown
        }
    }

    /// Maps a Statuspage `component.status` value.
    static func fromComponent(_ raw: String) -> Severity {
        switch raw {
        case "operational": return .operational
        case "degraded_performance": return .degraded
        case "partial_outage": return .partialOutage
        case "major_outage": return .majorOutage
        case "under_maintenance": return .maintenance
        default: return .unknown
        }
    }

    var label: String {
        switch self {
        case .operational: return L("Operational")
        case .degraded: return L("Degraded performance")
        case .partialOutage: return L("Partial outage")
        case .majorOutage: return L("Major outage")
        case .maintenance: return L("Under maintenance")
        case .unknown: return L("Unknown")
        }
    }

    var symbolName: String {
        switch self {
        case .operational: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.circle.fill"
        case .partialOutage: return "exclamationmark.triangle.fill"
        case .majorOutage: return "xmark.octagon.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}
