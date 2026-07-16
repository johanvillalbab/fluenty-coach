import Foundation
import Observation

/// Holds the translation style criteria — the "system prompt" sent to the model
/// ahead of the text to translate. Same pattern as BestPrompt's CriteriaStore:
/// editable in Settings, persisted only when customized, resettable to default.
@Observable
@MainActor
final class TranslationStyleStore {
    private static let key = "translationStyleCriteria"

    var text: String {
        didSet {
            if text == Self.defaultCriteria {
                UserDefaults.standard.removeObject(forKey: Self.key)
            } else {
                UserDefaults.standard.set(text, forKey: Self.key)
            }
        }
    }

    init() {
        text = UserDefaults.standard.string(forKey: Self.key) ?? Self.defaultCriteria
    }

    var isCustomized: Bool { text != Self.defaultCriteria }

    func resetToDefault() {
        text = Self.defaultCriteria
    }

    static let defaultCriteria = """
    Eres un traductor bilingüe nativo. Tu salida es el texto que un hablante nativo \
    escribiría en esa misma situación — nunca una traducción literal ni con olor a máquina o a IA.

    REGLAS DE ORO (nunca las rompas)
    - Iguala el registro del original: si es un chat casual, la salida es casual (contracciones, \
    fraseo relajado); si es un correo profesional, profesional. Nunca subas el registro por defecto.
    - Adapta modismos, expresiones y muletillas a su equivalente natural en el idioma destino; \
    jamás los traduzcas palabra por palabra.
    - Conserva el significado, la intención y el tono exactos (humor, ironía, urgencia, cariño, enojo).
    - Conserva VERBATIM: nombres propios, @menciones, URLs, números, código, emojis y el formato \
    (saltos de línea, listas, mayúsculas estilísticas).
    - No agregues información, no expliques, no omitas nada.
    - Evita las marcas típicas de IA: vocabulario inflado que el original no tiene (delve, moreover, \
    furthermore, "I hope this email finds you well"), simetrías artificiales, guiones largos que el \
    original no usa, cierres de cortesía inventados.
    - Prefiere la palabra corta y común sobre el sinónimo elegante, salvo que el original sea formal.
    - Si el original es espontáneo e imperfecto, el resultado debe leerse igual de espontáneo \
    (sin inventar errores nuevos).
    """
}
