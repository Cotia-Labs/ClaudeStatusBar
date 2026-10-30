import Foundation

/// Reads the plan's rate-limit windows from the endpoint that backs `/usage`
/// in Claude Code. Unofficial API: the shape may change without notice.
actor UsageFetcher {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// The endpoint buckets requests by User-Agent: anything that does not look
    /// like the CLI lands in a very tight bucket and starts returning 429.
    static let userAgent = "claude-cli/\(cliVersion) (external, cli)"
    static let profileEndpoint = URL(string: "https://api.anthropic.com/api/oauth/profile")!

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
            case .unauthorized: return L("Token expired. Sign in again from the menu.")
            case .throttled(let retryAfter):
                let wait = retryAfter.map { L(" Retrying in %d s.", Int($0.rounded())) } ?? ""
                return L("Rate limited by the server (429).") + wait
            case .http(let code): return L("Unexpected server response (HTTP %d).", code)
            }
        }
    }

    private let accessToken: @Sendable () async throws -> String
    private let invalidate: @Sendable () async -> Bool

    /// Padrão: a conta principal (login do app ou do Claude Code).
    init(accessToken: @escaping @Sendable () async throws -> String = { try await Credentials.accessToken() },
         invalidate: @escaping @Sendable () async -> Bool = { await Credentials.invalidate() }) {
        self.accessToken = accessToken
        self.invalidate = invalidate
    }

    /// A segunda conta só existe pelo login do app.
    static func login(_ login: AppLogin) -> UsageFetcher {
        UsageFetcher(accessToken: {
            guard let token = try await login.validAccessToken() else { throw Credentials.LookupError.notFound }
            return token
        }, invalidate: { await login.expire() })
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
        do {
            return try await attempt()
        } catch FetchError.unauthorized {
            // O token em cache pode ter sido rotacionado (pelo CLI ou expirado
            // antes da hora): relê ou renova uma vez antes de reportar o erro ao usuário.
            guard await invalidate() else { throw FetchError.unauthorized }
            return try await attempt()
        }
    }

    /// E-mail da conta, para o título do painel. Melhor esforço: sem ele o
    /// painel fica com "Conta 1"/"Conta 2".
    func email() async -> String? {
        struct Profile: Decodable {
            struct Account: Decodable { let email: String }
            let account: Account
        }
        guard let token = try? await accessToken() else { return nil }
        var request = URLRequest(url: Self.profileEndpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? decoder.decode(Profile.self, from: data))?.account.email
    }

    private func attempt() async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
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
