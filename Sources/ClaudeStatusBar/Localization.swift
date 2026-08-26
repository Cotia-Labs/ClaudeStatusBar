import Foundation

/// Base language is English: the keys *are* the English source strings, so the
/// bare executable (`swift run`, `--dump`) — which has no bundle and therefore
/// no `.lproj` — still prints readable text instead of dotted key names.
///
/// Translations live in `Resources/<lang>.lproj/Localizable.strings` and are
/// copied into `Contents/Resources` by `build-app.sh`.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Formatted variant. The format string itself is localized first, so a
/// translation may reorder arguments with `%1$@` / `%2$@`.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: .current, arguments: arguments)
}
