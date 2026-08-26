import Foundation

/// Latest release published on the public GitHub repo. Only the two fields we
/// need; the endpoint is anonymous (60 req/h por IP), sem token.
struct Release: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    /// "v1.0.7" -> "1.0.7".
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
}

/// Checks for a newer release and reports it once per version.
actor UpdateChecker {
    private static let endpoint = URL(
        string: "https://api.github.com/repos/Cotia-Labs/ClaudeStatusBar/releases/latest"
    )!

    /// The daily check is silent about failures (offline, rate limit); a manual
    /// check surfaces them, so the caller distinguishes the two via `throws`.
    func latest() async throws -> Release {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeStatusBar/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }
}

/// Compares dotted versions numerically, so 1.0.10 > 1.0.9.
func isVersion(_ candidate: String, newerThan current: String) -> Bool {
    let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
    let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(lhs.count, rhs.count) {
        let a = index < lhs.count ? lhs[index] : 0
        let b = index < rhs.count ? rhs[index] : 0
        if a != b { return a > b }
    }
    return false
}
