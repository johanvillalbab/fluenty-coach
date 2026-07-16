import Foundation

/// Which backend produces the translation. `.ai` runs through the Cursor CLI
/// (cursor-agent headless, reusing the user's Cursor login); `.deepl` is the
/// original DeepL REST API.
enum TranslationEngine: String, CaseIterable, Identifiable {
    case ai, deepl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ai: return "AI (Cursor)"
        case .deepl: return "DeepL"
        }
    }

    static let key = "translationEngine"

    static var current: TranslationEngine {
        get { UserDefaults.standard.string(forKey: key).flatMap(TranslationEngine.init) ?? .ai }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

@MainActor
final class TranslationService {
    private let state: TranslationState
    private let history: HistoryStore
    private let ai: AITranslationService
    private let session = URLSession.shared
    private var requestID = 0

    init(state: TranslationState, history: HistoryStore, ai: AITranslationService) {
        self.state = state
        self.history = history
        self.ai = ai
    }

    func translate(_ text: String) async {
        await translate(text, source: state.sourceLanguage, target: state.targetLanguage)
    }

    func translate(_ text: String, source: Language, target: Language) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        switch TranslationEngine.current {
        case .ai:
            await translateWithAI(text, source: source, target: target)
        case .deepl:
            await translateWithDeepL(text, source: source, target: target)
        }
    }

    // MARK: - AI engine (cursor-agent)

    private func translateWithAI(_ text: String, source: Language, target: Language) async {
        // Terminate any in-flight run so a retranslate doesn't race the old one.
        ai.cancel()

        requestID += 1
        let currentRequestID = requestID

        state.isLoading = true
        state.originalText = text
        state.translatedText = nil
        state.error = nil

        do {
            let result = try await ai.translate(
                text,
                source: source,
                target: target,
                flipTarget: flipTarget(from: target),
                context: state.sourceContext
            )

            guard currentRequestID == requestID else { return }

            // Mirror the DeepL auto-swap: if the model flipped because the text
            // was already in the target language, reflect the real direction.
            if source == .auto, result.usedTarget != target {
                state.targetLanguage = result.usedTarget
            }
            state.translatedText = result.text
            state.detectedSource = result.detectedSource
            history.add(original: text, translated: result.text, targetLanguage: result.usedTarget)
        } catch is CancellationError {
            return
        } catch {
            guard currentRequestID == requestID else { return }
            state.error = error.localizedDescription
        }

        if currentRequestID == requestID {
            state.isLoading = false
        }
    }

    // MARK: - DeepL engine

    private func translateWithDeepL(_ text: String, source: Language, target: Language) async {
        guard let apiKey = UserDefaults.standard.string(forKey: "deeplApiKey"), !apiKey.isEmpty else {
            state.showApiKeySetup = true
            return
        }

        requestID += 1
        let currentRequestID = requestID

        state.isLoading = true
        state.originalText = text
        state.translatedText = nil
        state.error = nil

        do {
            var effectiveTarget = target
            var result = try await performTranslation(
                text: text,
                sourceLang: source.deeplSourceCode,
                targetLang: target.deeplTargetCode,
                apiKey: apiKey,
                context: state.sourceContext
            )

            // Auto-swap: copying text already written in the target language makes
            // DeepL return it unchanged. Flip to the other side of the pair and
            // retranslate so the popover always shows a real translation (and the
            // no-op never reaches history).
            if source == .auto, let detected = result.detectedSource, detected == target {
                let flipped = flipTarget(from: target)
                let swapped = try await performTranslation(
                    text: text,
                    sourceLang: detected.deeplSourceCode,
                    targetLang: flipped.deeplTargetCode,
                    apiKey: apiKey,
                    context: state.sourceContext
                )
                guard currentRequestID == requestID else { return }
                effectiveTarget = flipped
                state.targetLanguage = flipped
                result = (swapped.text, detected)
            }

            guard currentRequestID == requestID else { return }
            state.translatedText = result.text
            state.detectedSource = result.detectedSource
            history.add(original: text, translated: result.text, targetLanguage: effectiveTarget)
        } catch {
            guard currentRequestID == requestID else { return }
            state.error = error.localizedDescription
        }

        if currentRequestID == requestID {
            state.isLoading = false
        }
    }

    /// The language to retranslate into when the copied text is already in the
    /// current target: anything → English, English → the user's home target.
    private func flipTarget(from target: Language) -> Language {
        if target != .en { return .en }
        return state.homeTarget != .en ? state.homeTarget : .es
    }

    private func performTranslation(
        text: String,
        sourceLang: String?,
        targetLang: String,
        apiKey: String,
        context: String?
    ) async throws -> (text: String, detectedSource: Language?) {
        let endpoint = "https://api-free.deepl.com/v2/translate"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // When sourceLang is nil, DeepL auto-detects the source language.
        var body: [String: Any] = [
            "text": [text],
            "target_lang": targetLang,
            // Informal register ("tú" over "usted"). The prefer_ variant falls
            // back silently on languages without a formality distinction.
            "formality": "prefer_less"
        ]
        if let sourceLang { body["source_lang"] = sourceLang }
        // Surrounding text that influences the translation but is not itself
        // translated. DeepL does not bill characters sent in `context`.
        if let context, !context.isEmpty { body["context"] = context }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "DeepL", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: friendlyMessage(for: httpResponse.statusCode, raw: msg)])
        }

        let decoded = try JSONDecoder().decode(DeepLResponse.self, from: data)
        guard let translation = decoded.translations.first else {
            throw NSError(domain: "DeepL", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No translation returned"])
        }
        let detected = translation.detectedSourceLanguage.map { Language(deeplDetected: $0) }
        return (translation.text, detected)
    }

    private func friendlyMessage(for statusCode: Int, raw: String) -> String {
        switch statusCode {
        case 403: return "Invalid DeepL API key. Check it in Settings."
        case 456: return "DeepL quota reached for this month."
        case 429: return "Too many requests — wait a moment and try again."
        default: return raw
        }
    }
}

private struct DeepLResponse: Decodable {
    let translations: [DeepLTranslation]
}

private struct DeepLTranslation: Decodable {
    let detectedSourceLanguage: String?
    let text: String

    enum CodingKeys: String, CodingKey {
        case detectedSourceLanguage = "detected_source_language"
        case text
    }
}
