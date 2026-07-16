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

    /// The resting "Auto → X" target. Persisted; changed via the dropdown.
    var homeTarget: Language = TranslationState.loadHomeTarget() {
        didSet { TranslationState.saveHomeTarget(homeTarget) }
    }

    /// Working direction for the current session. Resets to Auto → homeTarget on
    /// each launch so the default is always "Auto → Spanish"; the swap button
    /// flips it within a session.
    var sourceLanguage: Language = .auto
    var targetLanguage: Language = TranslationState.loadHomeTarget()

    /// Source language DeepL reported for the last translation (used to show what
    /// "Auto" detected, to pick the swap-to language, and for pronunciation).
    var detectedSource: Language? = nil

    /// Text surrounding the copied selection in the source app, captured at
    /// copy time. Sent to DeepL as the unbilled `context` parameter so short
    /// fragments translate with their surroundings in mind. Nil when the
    /// focused element exposes no text (or Accessibility is not granted).
    var sourceContext: String? = nil

    var sourceElement: AXUIElement? = nil
    var sourceAppPID: pid_t? = nil
    var sourceSelectionRange: NSRange? = nil
    var showApiKeySetup: Bool = false

    /// The language shown on the source side: the detected one while on Auto,
    /// otherwise the explicit source chosen by a swap.
    var displayedSource: Language {
        sourceLanguage == .auto ? (detectedSource ?? .auto) : sourceLanguage
    }

    /// Flip the translation direction in place.
    /// Auto → target  ⇄  target → (detected language).
    func swapLanguages() {
        if sourceLanguage == .auto {
            let detected = detectedSource ?? .en
            let flipTarget = (detected == .auto || detected == targetLanguage) ? .en : detected
            sourceLanguage = targetLanguage
            targetLanguage = flipTarget
        } else {
            sourceLanguage = .auto
            targetLanguage = homeTarget
        }
    }

    /// Pick a new resting target from the dropdown; resets to Auto → newTarget.
    func selectHomeTarget(_ language: Language) {
        homeTarget = language
        sourceLanguage = .auto
        targetLanguage = language
    }

    // MARK: - Persistence

    private static let homeTargetKey = "homeTargetLanguage"

    static func loadHomeTarget() -> Language {
        if let raw = UserDefaults.standard.string(forKey: homeTargetKey),
           let lang = Language(rawValue: raw), lang != .auto {
            return lang
        }
        return .es
    }

    static func saveHomeTarget(_ language: Language) {
        UserDefaults.standard.set(language.rawValue, forKey: homeTargetKey)
    }
}
