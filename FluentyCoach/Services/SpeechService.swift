import AVFoundation
import Observation

/// Speaks text aloud for pronunciation practice. Uses the system speech
/// synthesizer, which needs no special permission. `isSpeaking` is observable
/// so buttons can reflect playback state.
@Observable
@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak `text` using the best available voice for `language`. If the same
    /// text is already playing, this stops it (tap-to-toggle behavior).
    func speak(_ text: String, language: Language) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            return
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = SpeechService.bestVoice(for: language.speechCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.prefersAssistiveTechnologySettings = false
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private static func bestVoice(for code: String) -> AVSpeechSynthesisVoice? {
        if let exact = AVSpeechSynthesisVoice(language: code) { return exact }
        // Fall back to any voice sharing the language prefix, else system default.
        let prefix = code.prefix(2).lowercased()
        return AVSpeechSynthesisVoice.speechVoices()
            .first { $0.language.lowercased().hasPrefix(prefix) }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
