import Foundation
import Security

/// Locates the Claude Code OAuth access token the same way the CLI does:
/// `~/.claude/.credentials.json` first, then the login keychain item that the
/// native builds use. The token never leaves this process except as the
/// Authorization header sent to api.anthropic.com.
enum Credentials {
    private static let keychainService = "Claude Code-credentials"

    /// O token fica em memória entre os refreshes. Sem isso cada ciclo do timer
    /// bate no keychain, e como o app é assinado ad-hoc a ACL não cola: o
    /// macOS volta a pedir autorização de tempos em tempos. Uma leitura por
    /// execução (ou por 401) reduz o prompt ao mínimo inevitável.
    private static let cacheLock = NSLock()
    private static var cachedToken: String?

    /// Chamado quando a API recusa o token. Retorna `true` se havia mesmo um
    /// token em cache — só nesse caso vale reler a fonte, porque um token
    /// recém-lido que já veio recusado não muda numa segunda tentativa (e a
    /// releitura custaria outro prompt do keychain).
    @discardableResult
    static func invalidate() -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let had = cachedToken != nil
        cachedToken = nil
        return had
    }

    enum LookupError: LocalizedError {
        case notFound

        var errorDescription: String? {
            L("No Claude Code token found. Sign in with `claude` and try again.")
        }
    }

    static func accessToken() throws -> String {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let token = cachedToken { return token }
        guard let token = tokenFromFile() ?? tokenFromKeychain() else {
            throw LookupError.notFound
        }
        cachedToken = token
        return token
    }

    private static func tokenFromFile() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parseToken(from: data)
    }

    private static func tokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return parseToken(from: data)
    }

    /// The payload is `{"claudeAiOauth": {"accessToken": "..."}}`, but the exact
    /// nesting has shifted across releases, so search for the key anywhere.
    private static func parseToken(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return findToken(in: root)
    }

    private static func findToken(in object: Any) -> String? {
        if let dict = object as? [String: Any] {
            for key in ["accessToken", "access_token"] {
                if let token = dict[key] as? String, !token.isEmpty { return token }
            }
            for value in dict.values {
                if let token = findToken(in: value) { return token }
            }
        }
        return nil
    }
}
