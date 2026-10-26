import CryptoKit
import Foundation

/// Login OAuth do próprio app (PKCE, o mesmo fluxo do `claude auth login`),
/// para quem não usa o Claude Code. O token fica num arquivo `0600` em vez do
/// keychain: o item do CLI é regravado a cada refresh e perde o "Sempre
/// permitir", e a assinatura ad-hoc faz cada versão do app parecer outro app.
/// A proteção é a mesma do `~/.claude/.credentials.json` do CLI.
actor AppLogin {
    static let shared = AppLogin()

    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let authorizeURL = URL(string: "https://claude.com/cai/oauth/authorize")!
    private static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    private static let scope = "user:profile user:inference"

    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ClaudeStatusBar/token.json")

    enum LoginError: LocalizedError {
        case invalidCode
        case rejected(Int)

        var errorDescription: String? {
            switch self {
            case .invalidCode: return L("Invalid code. Start the sign-in again and paste the whole code.")
            case .rejected(let code): return L("Sign-in failed (HTTP %d).", code)
            }
        }
    }

    private struct StoredToken: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    private var token: StoredToken?
    private var loaded = false
    private var pending: (verifier: String, state: String)?
    /// O refresh token roda a cada uso: dois refreshes em paralelo fariam o
    /// segundo usar um token já trocado, e o login cairia.
    private var refreshing: Task<StoredToken, Error>?

    /// Leitura barata para o menu decidir entre "Entrar" e "Sair".
    nonisolated static var isSignedIn: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    // MARK: - Login

    /// Gera o PKCE e devolve a URL a abrir no navegador.
    func beginLogin() -> URL {
        let verifier = Self.randomURLSafe()
        let state = Self.randomURLSafe()
        pending = (verifier, state)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: Self.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: Self.scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        return components.url!
    }

    /// Troca o código colado (`code#state`) pelo par de tokens.
    func finishLogin(code pasted: String) async throws {
        let parts = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "#", maxSplits: 1).map(String.init)
        guard let pending, let code = parts.first, !code.isEmpty,
              parts.count == 1 || parts[1] == pending.state else { throw LoginError.invalidCode }
        let fresh = try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "state": pending.state,
            "redirect_uri": Self.redirectURI,
            "client_id": Self.clientID,
            "code_verifier": pending.verifier,
        ])
        self.pending = nil
        try save(fresh)
    }

    func signOut() {
        token = nil
        loaded = true
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    // MARK: - Token

    /// `nil` quando não há login próprio; renova se faltar pouco para expirar.
    func validAccessToken() async throws -> String? {
        if !loaded {
            loaded = true
            token = (try? Data(contentsOf: Self.fileURL))
                .flatMap { try? JSONDecoder().decode(StoredToken.self, from: $0) }
        }
        guard let current = token else { return nil }
        if current.expiresAt.timeIntervalSinceNow > 300 { return current.accessToken }
        return try await refresh(current).accessToken
    }

    /// A API recusou o token: força um refresh na próxima leitura.
    /// Retorna `false` se não há login próprio.
    func expire() -> Bool {
        guard token != nil else { return false }
        token?.expiresAt = .distantPast
        return true
    }

    private func refresh(_ current: StoredToken) async throws -> StoredToken {
        if let refreshing { return try await refreshing.value }
        let task = Task {
            try await requestToken([
                "grant_type": "refresh_token",
                "refresh_token": current.refreshToken,
                "client_id": Self.clientID,
                "scope": Self.scope,
            ])
        }
        refreshing = task
        defer { refreshing = nil }
        do {
            let fresh = try await task.value
            try save(fresh)
            return fresh
        } catch LoginError.rejected(let code) where (400..<500).contains(code) && code != 429 {
            // Refresh token revogado ou vencido (~30 dias sem uso): só um novo
            // login resolve. Erro de rede não apaga nada.
            signOut()
            throw Credentials.LookupError.notFound
        }
    }

    private func requestToken(_ body: [String: String]) async throws -> StoredToken {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Sem um User-Agent de CLI o Cloudflare responde 403 (erro 1010).
        request.setValue(UsageFetcher.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw LoginError.rejected(status) }

        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return StoredToken(accessToken: decoded.access_token,
                           refreshToken: decoded.refresh_token ?? body["refresh_token"] ?? "",
                           expiresAt: Date().addingTimeInterval(decoded.expires_in))
    }

    private func save(_ fresh: StoredToken) throws {
        let manager = FileManager.default
        let directory = Self.fileURL.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(fresh).write(to: Self.fileURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
        token = fresh
        loaded = true
    }

    private static func randomURLSafe() -> String {
        base64URL(Data(SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
