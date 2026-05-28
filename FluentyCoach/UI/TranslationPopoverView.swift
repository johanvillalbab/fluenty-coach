import SwiftUI
import AppKit

struct TranslationPopoverView: View {
    @Bindable var state: TranslationState
    let translation: TranslationService
    let accessibility: AccessibilityService
    let onDismiss: () -> Void

    var hasTranslation: Bool { state.translatedText != nil && !state.isLoading }
    var canReplace: Bool { hasTranslation }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "translate")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                LanguageToggleView(direction: languageDirectionBinding)

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
                .frame(minHeight: 70, maxHeight: 110)

            Divider()
                .opacity(0.25)

            // ── Action buttons ───────────────────────────────
            HStack(spacing: 6) {
                Spacer()

                GlassActionButton(
                    title: "Replace",
                    systemImage: "arrow.triangle.2.circlepath",
                    isDisabled: !canReplace
                ) {
                    guard let text = state.translatedText else { return }
                    accessibility.replaceSelection(
                        in: state.sourceAppPID,
                        with: text
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
        .background(.ultraThinMaterial)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.07), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.32), .white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
    }

    private var languageDirectionBinding: Binding<TranslationDirection> {
        Binding(
            get: { state.direction },
            set: { newDirection in
                guard newDirection != state.direction else { return }
                state.direction = newDirection
                retranslate(using: newDirection)
            }
        )
    }

    private func retranslate(using direction: TranslationDirection) {
        let textToRetranslate = state.originalText
        guard !textToRetranslate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        Task { @MainActor in
            await translation.translate(textToRetranslate, direction: direction)
        }
    }
}
