import SwiftUI
import AppKit

struct HistoryView: View {
    @Bindable var store: HistoryStore
    let speech: SpeechService

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if store.records.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.records) { record in
                            HistoryRow(record: record, speech: speech, store: store)
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
        .frame(width: 420, height: 460)
    }

    private var header: some View {
        HStack {
            Label("History", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if !store.records.isEmpty {
                Button(role: .destructive) {
                    store.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("No translations yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Select text anywhere and press ⌘C twice.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryRow: View {
    let record: TranslationRecord
    let speech: SpeechService
    let store: HistoryStore

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(record.targetLanguage.flag)
                    .font(.system(size: 11))
                Text(record.targetLanguage.shortCode)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(record.date, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Text(record.original)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(record.translated)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(3)

            HStack(spacing: 14) {
                iconButton(copied ? "checkmark" : "doc.on.doc", help: "Copy translation") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(record.translated, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                iconButton("speaker.wave.2.fill", help: "Listen") {
                    speech.speak(record.translated, language: record.targetLanguage)
                }
                Spacer()
                iconButton("trash", help: "Delete", tint: .secondary) {
                    store.remove(record)
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func iconButton(_ name: String, help: String, tint: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
