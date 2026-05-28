import Foundation

@MainActor
final class TranslationService {
    private let state: TranslationState
    private let session = URLSession.shared
    private var requestID = 0

    init(state: TranslationState) {
        self.state = state
    }

    func translate(_ text: String) async {
        await translate(text, direction: state.direction)
    }

    func translate(_ text: String, direction: TranslationDirection) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

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
            let result = try await performTranslation(
                text: text,
                targetLang: direction.deeplTargetCode,
                apiKey: apiKey
            )
            guard currentRequestID == requestID else { return }
            state.translatedText = result
        } catch {
            guard currentRequestID == requestID else { return }
            state.error = error.localizedDescription
        }

        if currentRequestID == requestID {
            state.isLoading = false
        }
    }

    private func performTranslation(
        text: String,
        targetLang: String,
        apiKey: String
    ) async throws -> String {
        let endpoint = "https://api-free.deepl.com/v2/translate"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": [text],
            "target_lang": targetLang
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "DeepL", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let decoded = try JSONDecoder().decode(DeepLResponse.self, from: data)
        guard let translation = decoded.translations.first?.text else {
            throw NSError(domain: "DeepL", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No translation returned"])
        }
        return translation
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
