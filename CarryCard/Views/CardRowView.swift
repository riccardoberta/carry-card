import SwiftUI

/// A single wallet-style card. Two sizes: `.featured` for the prominent
/// "recently used" card at the top of the list, and `.grid` for the compact
/// two-column tiles below it. Neither ever shows the full barcode — that's the
/// detail screen's job.
struct CardRowView: View {
    enum Style {
        case featured
        case grid
    }

    let card: LoyaltyCard
    let imageStore: ImageStore
    var style: Style = .grid

    var body: some View {
        ZStack(alignment: style == .featured ? .center : .bottomLeading) {
            RoundedRectangle(cornerRadius: style == .featured ? 24 : 18, style: .continuous)
                .fill(cardBackground)

            content
        }
        .frame(height: style == .featured ? 132 : 138)
        .shadow(color: .black.opacity(style == .featured ? 0.22 : 0.14), radius: style == .featured ? 12 : 7, x: 0, y: style == .featured ? 7 : 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.name)
        .accessibilityHint("Loyalty card. Double tap to view barcode.")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .featured:
            HStack(spacing: 16) {
                LogoView(imageStore: imageStore, fileName: card.logoFileName, merchantName: card.name, size: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recently Used")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(card.name)
                        .font(.title3.weight(.semibold))
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
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

        case .grid:
            VStack(alignment: .leading, spacing: 0) {
                LogoView(imageStore: imageStore, fileName: card.logoFileName, merchantName: card.name, size: 38)
                Spacer(minLength: 8)
                Text(card.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("···· \(card.codeSuffix)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(14)
        }
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
        VStack(spacing: 16) {
            CardRowView(card: PreviewData.sampleCards[0], imageStore: PreviewData.imageStore, style: .featured)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(PreviewData.sampleCards) { card in
                    CardRowView(card: card, imageStore: PreviewData.imageStore, style: .grid)
                }
            }
        }
        .padding()
    }
}
