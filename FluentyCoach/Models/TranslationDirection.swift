import Foundation

enum TranslationDirection: String, CaseIterable {
    case enToEs = "enToEs"
    case esToEn = "esToEn"

    var label: String {
        switch self {
        case .enToEs: return "EN → ES"
        case .esToEn: return "ES → EN"
        }
    }

    var sourceCode: String {
        self == .enToEs ? "EN" : "ES"
    }

    var targetCode: String {
        self == .enToEs ? "ES" : "EN"
    }

    var deeplTargetCode: String {
        self == .enToEs ? "ES" : "EN-US"
    }

    var toggled: TranslationDirection {
        self == .enToEs ? .esToEn : .enToEs
    }
}
