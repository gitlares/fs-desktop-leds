import Foundation

public enum AppLanguage {
    /// Bundle selection honors macOS language order and per-app language overrides.
    public static let current = resolve(Bundle.main.preferredLocalizations)
    public static func resolve(_ preferences: [String]) -> String {
        for preference in preferences {
            let language = preference.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if language == "es" { return "es" }
            if language == "en" { return "en" }
        }
        return "en"
    }
}

/// Explicit bilingual strings also support dynamically generated menu titles.
public func L(_ english: String, _ spanish: String) -> String {
    AppLanguage.current == "es" ? spanish : english
}
