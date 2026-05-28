import SwiftUI

struct LanguageToggleView: View {
    @Binding var direction: TranslationDirection

    var body: some View {
        Button {
            let newDirection = direction.toggled
            withAnimation(.spring(duration: 0.25)) {
                direction = newDirection
            }
        } label: {
            HStack(spacing: 5) {
                Text(direction.sourceCode)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                Text(direction.targetCode)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
