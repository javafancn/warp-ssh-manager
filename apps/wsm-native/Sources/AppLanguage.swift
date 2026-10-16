import Foundation

/// Runtime language preference. Source UI keys are written in Chinese; the
/// .strings resources supply the English equivalents. Keep user data verbatim.
enum AppLanguage {
    static let didChange=Notification.Name("wsm.language.changed")
    static func identifier(_ choice:String) -> String {
        switch choice {
        case "en": return "en"
        case "zh-Hans": return "zh-Hans"
        default:
            let first=Locale.preferredLanguages.first ?? "en"
            return first.hasPrefix("zh") ? "zh-Hans" : "en"
        }
    }
    static func locale(_ choice:String) -> Locale {
        Locale(identifier:identifier(choice))
    }
    static func text(_ key:String) -> String {
        let selected=UserDefaults.standard.string(forKey:"warp.language") ?? "system"
        let language=identifier(selected)
        if language == "zh-Hans" {return key}
        guard let path=Bundle.main.path(forResource:"en",ofType:"lproj"),
              let bundle=Bundle(path:path) else {return key}
        return bundle.localizedString(forKey:key,value:key,table:"Localizable")
    }
}
