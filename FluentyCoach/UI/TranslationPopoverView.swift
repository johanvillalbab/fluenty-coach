import SwiftUI
import AppKit

struct TranslationPopoverView: View {
    @Bindable var state: TranslationState
    let translation: TranslationService
    let accessibility: AccessibilityService
    let speech: SpeechService
    let onDismiss: () -> Void

    var hasTranslation: Bool { state.translatedText != nil && !state.isLoading }
    var canReplace: Bool { hasTranslation }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "character.bubble")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                // Retranslate on explicit user actions only — the service also
                // updates targetLanguage during auto-swap, and reacting to that
                // change would fire a redundant request.
                LanguagePickerBar(
                    source: state.displayedSource,
                    target: state.targetLanguage,
                    onSwap: {
                        state.swapLanguages()
                        retranslate()
                    },
                    onSelectTarget: {
                        state.selectHomeTarget($0)
                        retranslate()
                    }
                )

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 11)
            .padding(.bottom, 8)

            Divider()
                .opacity(0.25)

            // ── Translation result ───────────────────────────
            TranslationResultView(state: state)
                .frame(maxWidth: .infinity)
                .frame(height: 104)

            Divider()
                .opacity(0.25)

            // ── Action buttons ───────────────────────────────
            HStack(spacing: 6) {
                // Listen / pronounce the translation in the target language.
                GlassActionButton(
                    title: speech.isSpeaking ? "Stop" : "Listen",
                    systemImage: speech.isSpeaking ? "stop.fill" : "speaker.wave.2.fill",
                    isDisabled: !hasTranslation
                ) {
                    guard let text = state.translatedText else { return }
                    speech.speak(text, language: state.targetLanguage)
                }

                Spacer()

                GlassActionButton(
                    title: "Replace",
                    systemImage: "arrow.triangle.2.circlepath",
                    isDisabled: !canReplace
                ) {
                    guard let text = state.translatedText else { return }
                    accessibility.replaceTranslation(
                        in: state.sourceElement,
                        pid: state.sourceAppPID,
                        with: text,
                        selectedRange: state.sourceSelectionRange
                    ) { onDismiss() }
                }

                GlassActionButton(
                    title: "Copy",
                    systemImage: "doc.on.doc",
                    isDisabled: !hasTranslation
                ) {
                    guard let text = state.translatedText else { return }
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(width: 320)
        // Liquid Glass surface (same treatment as TimerStack): the glass provides
        // the rounded edge and depth — no manual material/stroke/shadow, which is
        // what previously bled a hard-cornered rectangle around the panel.
        .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
        .focusEffectDisabled()
    }

    private func retranslate() {
        let textToRetranslate = state.originalText
        guard !textToRetranslate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        Task { @MainActor in
            await translation.translate(
                textToRetranslate,
                source: state.sourceLanguage,
                target: state.targetLanguage
            )
        }
    }
}
