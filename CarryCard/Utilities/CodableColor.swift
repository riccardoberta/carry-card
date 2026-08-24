import SwiftUI

/// A `Codable`, `Equatable` color representation independent of platform color types,
/// so it can round-trip cleanly through JSON in the local and synced databases.
struct CodableColor: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(color: Color) {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
        #else
        self.init(red: 0, green: 0, blue: 0, opacity: 1)
        #endif
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }

    /// A pleasant, deterministic default palette used when creating new cards.
    static let defaultPalette: [CodableColor] = [
        CodableColor(red: 0.16, green: 0.35, blue: 0.74), // blue
        CodableColor(red: 0.14, green: 0.58, blue: 0.44), // green
        CodableColor(red: 0.75, green: 0.22, blue: 0.24), // red
        CodableColor(red: 0.55, green: 0.28, blue: 0.68), // purple
        CodableColor(red: 0.86, green: 0.53, blue: 0.09), // orange
        CodableColor(red: 0.20, green: 0.20, blue: 0.24), // charcoal
        CodableColor(red: 0.09, green: 0.55, blue: 0.60), // teal
        CodableColor(red: 0.72, green: 0.30, blue: 0.49)  // magenta
    ]

    /// Deterministically derives a palette color from a merchant name so
    /// new cards look distinct without requiring the user to pick a color.
    static func derived(from name: String) -> CodableColor {
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        let index = abs(hash) % defaultPalette.count
        return defaultPalette[index]
    }
}
