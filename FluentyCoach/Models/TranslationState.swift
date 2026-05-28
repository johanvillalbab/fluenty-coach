import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class TranslationState {
    var originalText: String = ""
    var translatedText: String? = nil
    var isLoading: Bool = false
    var error: String? = nil
    var direction: TranslationDirection = .enToEs
    var sourceElement: AXUIElement? = nil
    var sourceAppPID: pid_t? = nil
    var sourceSelectionRange: NSRange? = nil
    var showApiKeySetup: Bool = false
}
