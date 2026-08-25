import Foundation

enum StatusFetchError: Error { case badResponse(Int) }

/// Polls the public Anthropic status page.
actor StatusFetcher {
    static let summaryURL = URL(string: "https://status.anthropic.com/api/v2/summary.json")!

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return decoder
    }()

    func fetch() async throws -> StatusSummary {
        var request = URLRequest(url: Self.summaryURL)
        request.setValue("ClaudeStatusBar/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StatusFetchError.badResponse(http.statusCode)
        }
        return try decoder.decode(StatusSummary.self, from: data)
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    /// Statuspage emits offsets like `2026-08-25T12:00:00.123-07:00`, which the plain
    /// `.iso8601` strategy rejects because of the fractional seconds.
    static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        return .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: raw) ?? plain.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Data inválida: \(raw)")
            )
        }
    }
}
