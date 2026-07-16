import Foundation

/// A language Fluenty can translate into (and speak). DeepL auto-detects the
/// source language, so `.auto` is only ever used to represent "let DeepL decide".
enum Language: String, CaseIterable, Identifiable, Codable {
    case auto
    case en, es, fr, de, it, pt, nl, pl, ru, ja, zh, ko, tr, uk

    var id: String { rawValue }

    /// Languages a user can pick as a translation target (everything except auto).
    static var targets: [Language] { allCases.filter { $0 != .auto } }

    /// Source code understood by the DeepL `source_lang` parameter.
    /// `nil` for `.auto`, which means "let DeepL detect the source".
    var deeplSourceCode: String? {
        self == .auto ? nil : rawValue.uppercased()
    }

    /// Target code understood by the DeepL `target_lang` parameter.
    var deeplTargetCode: String {
        switch self {
        case .auto, .en: return "EN-US"
        case .es: return "ES"
        case .fr: return "FR"
        case .de: return "DE"
        case .it: return "IT"
        case .pt: return "PT-PT"
        case .nl: return "NL"
        case .pl: return "PL"
        case .ru: return "RU"
        case .ja: return "JA"
        case .zh: return "ZH"
        case .ko: return "KO"
        case .tr: return "TR"
        case .uk: return "UK"
        }
    }

    /// BCP-47 locale used by the speech synthesizer for pronunciation.
    var speechCode: String {
        switch self {
        case .auto, .en: return "en-US"
        case .es: return "es-ES"
        case .fr: return "fr-FR"
        case .de: return "de-DE"
        case .it: return "it-IT"
        case .pt: return "pt-PT"
        case .nl: return "nl-NL"
        case .pl: return "pl-PL"
        case .ru: return "ru-RU"
        case .ja: return "ja-JP"
        case .zh: return "zh-CN"
        case .ko: return "ko-KR"
        case .tr: return "tr-TR"
        case .uk: return "uk-UA"
        }
    }

    var flag: String {
        switch self {
        case .auto: return "🌐"
        case .en: return "🇬🇧"
        case .es: return "🇪🇸"
        case .fr: return "🇫🇷"
        case .de: return "🇩🇪"
        case .it: return "🇮🇹"
        case .pt: return "🇵🇹"
        case .nl: return "🇳🇱"
        case .pl: return "🇵🇱"
        case .ru: return "🇷🇺"
        case .ja: return "🇯🇵"
        case .zh: return "🇨🇳"
        case .ko: return "🇰🇷"
        case .tr: return "🇹🇷"
        case .uk: return "🇺🇦"
        }
    }

    var displayName: String {
        switch self {
        case .auto: return "Auto-detect"
        case .en: return "English"
        case .es: return "Spanish"
        case .fr: return "French"
        case .de: return "German"
        case .it: return "Italian"
        case .pt: return "Portuguese"
        case .nl: return "Dutch"
        case .pl: return "Polish"
        case .ru: return "Russian"
        case .ja: return "Japanese"
        case .zh: return "Chinese"
        case .ko: return "Korean"
        case .tr: return "Turkish"
        case .uk: return "Ukrainian"
        }
    }

    /// Short uppercase tag shown in compact UI (EN, ES, …).
    var shortCode: String {
        self == .auto ? "AUTO" : rawValue.uppercased()
    }

    /// Map a DeepL `detected_source_language` value (e.g. "EN", "PT-BR") to a Language.
    init(deeplDetected code: String) {
        let normalized = code.uppercased().prefix(2)
        switch normalized {
        case "EN": self = .en
        case "ES": self = .es
        case "FR": self = .fr
        case "DE": self = .de
        case "IT": self = .it
        case "PT": self = .pt
        case "NL": self = .nl
        case "PL": self = .pl
        case "RU": self = .ru
        case "JA": self = .ja
        case "ZH": self = .zh
        case "KO": self = .ko
        case "TR": self = .tr
        case "UK": self = .uk
        default: self = .auto
        }
    }
}
