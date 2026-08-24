import SwiftUI

/// Shows a merchant logo loaded asynchronously from `ImageStore`, or an elegant
/// initials placeholder when there is no logo (or it fails to load).
struct LogoView: View {
    let imageStore: ImageStore
    let fileName: String?
    let merchantName: String
    var size: CGFloat = 44

    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .task(id: fileName) { await loadImage() }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(.white.opacity(0.22))
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let letters = merchantName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private func loadImage() async {
        guard let fileName else {
            uiImage = nil
            return
        }
        if let data = await imageStore.loadImageData(fileName: fileName) {
            uiImage = UIImage(data: data)
        } else {
            uiImage = nil
        }
    }
}
