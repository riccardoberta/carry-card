import SwiftUI

/// A single wallet-style card in the main list: logo, merchant name, and a
/// hint of the loyalty code — never the full barcode, which lives on the
/// detail screen.
struct CardRowView: View {
    let card: LoyaltyCard
    let imageStore: ImageStore

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardBackground)

            HStack(spacing: 14) {
                LogoView(imageStore: imageStore, fileName: card.logoFileName, merchantName: card.name, size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("···· \(card.codeSuffix)")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.white.opacity(0.78))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .frame(height: 108)
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.name)
        .accessibilityHint("Loyalty card. Double tap to view barcode.")
        .accessibilityAddTraits(.isButton)
    }

    private var cardBackground: LinearGradient {
        let base = (card.backgroundColor ?? CodableColor.derived(from: card.name)).color
        return LinearGradient(
            colors: [base, base.opacity(0.82)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    ScrollView {
        VStack(spacing: -30) {
            ForEach(PreviewData.sampleCards) { card in
                CardRowView(card: card, imageStore: PreviewData.imageStore)
            }
        }
        .padding()
    }
}
