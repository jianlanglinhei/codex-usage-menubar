import Foundation

enum Language {
    case chinese, english

    /// Follows the user's first preferred language, including the per-app override in System Settings.
    static var current: Language = Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .chinese : .english

    /// `Locale.current` is clamped to the bundle's localizations, so build the locale from the chosen language plus the user's region.
    var locale: Locale {
        let region = Locale.current.region?.identifier ?? (self == .chinese ? "CN" : "US")
        return Locale(identifier: (self == .chinese ? "zh_Hans_" : "en_") + region)
    }
}

func tr(_ chinese: String, _ english: String) -> String {
    Language.current == .chinese ? chinese : english
}

/// "10月7日 12:41" / "Oct 7, 12:41 PM", honouring the region's 12/24-hour preference.
func shortDateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Language.current.locale
    formatter.timeZone = .autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate("MMMdjmm")
    return formatter.string(from: date)
}
