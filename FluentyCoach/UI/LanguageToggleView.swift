import SwiftUI

/// Header bar: source → target, with a swap button sitting *between* the two
/// languages that flips the direction (Auto→ES ⇄ ES→EN) and retranslates.
struct LanguagePickerBar: View {
    let source: Language
    let target: Language
    let onSwap: () -> Void
    let onSelectTarget: (Language) -> Void

    var body: some View {
        HStack(spacing: 5) {
            // Source side (read-only): shows what Auto detected, or the explicit
            // source after a swap.
            chip(flag: source.flag, code: source.shortCode)

            // Swap button — between the languages, like a translator's ⇄.
            Button(action: onSwap) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(6)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .help("Swap languages")

            // Target side: tap to change the resting language.
            Menu {
                ForEach(Language.targets) { lang in
                    Button {
                        onSelectTarget(lang)
                    } label: {
                        if lang == target {
                            Label("\(lang.flag)  \(lang.displayName)", systemImage: "checkmark")
                        } else {
                            Text("\(lang.flag)  \(lang.displayName)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(target.flag).font(.system(size: 11))
                    Text(target.shortCode)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            // .button menu style + plain button style renders the full custom label
            // (the older .borderlessButton clipped it to just the flag and showed a
            // stray system chevron).
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func chip(flag: String, code: String) -> some View {
        HStack(spacing: 4) {
            Text(flag).font(.system(size: 11))
            Text(code)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }
}
