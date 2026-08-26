import Foundation

/// Reads the plan's rate-limit windows from the endpoint that backs `/usage`
/// in Claude Code. Unofficial API: the shape may change without notice.
actor UsageFetcher {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// The endpoint buckets requests by User-Agent: anything that does not look
    /// like the CLI lands in a very tight bucket and starts returning 429.
    private static let userAgent = "claude-cli/\(cliVersion) (external, cli)"

    /// Best effort read of the installed CLI version, so the header tracks it.
    private static let cliVersion: String = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/version")
        if let raw = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "2.1.245"
    }()

    enum FetchError: LocalizedError {
        case unauthorized
        case throttled(retryAfter: TimeInterval?)
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .unauthorized: return L("Token expired. Run `claude` to sign in again.")
            case .throttled(let retryAfter):
                let wait = retryAfter.map { L(" Retrying in %d s.", Int($0.rounded())) } ?? ""
                return L("Rate limited by the server (429).") + wait
            case .http(let code): return L("Unexpected server response (HTTP %d).", code)
            }
        }
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .flexibleISO8601
        return decoder
    }()

    func fetch() async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(try Credentials.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            switch http.statusCode {
            case 401, 403: throw FetchError.unauthorized
            case 429:
                let header = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                throw FetchError.throttled(retryAfter: header.flatMap { $0 > 0 ? $0 : nil })
            default: throw FetchError.http(http.statusCode)
            }
        }
        return try decoder.decode(UsageSnapshot.self, from: data)
    }
}

extension JSONDecoder.DateDecodingStrategy {
    /// Accepts ISO-8601 with or without fractional seconds, plus epoch seconds,
    /// since `resets_at` has appeared in both forms.
    static var flexibleISO8601: JSONDecoder.DateDecodingStrategy {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        return .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let raw = try? container.decode(String.self) {
                if let date = withFraction.date(from: raw) ?? plain.date(from: raw) { return date }
            }
            if let epoch = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: epoch)
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Data inválida")
            )
        }
    }
}
