import SwiftUI

// MARK: - Crux Design Tokens
//
// Crux's visual identity: a warm, literary bronze drawn from the reading
// surface's typographic palette (see Resources/Reader/reader.css,
// --crux-accent). Centralizing the brand colors here keeps the SwiftUI
// chrome and the WebView reading surface in the same visual family, and
// gives every view one place to pull accents from instead of scattering
// hex values.

extension Color {
    /// Brand accent: deep bronze in light mode, soft amber in dark mode.
    /// Mirrors the reader CSS accent (#8B4513 light / #D4A574 dark) so
    /// chrome and page feel like one product.
    static var cruxAccent: Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.831, green: 0.647, blue: 0.455, alpha: 1.0) // #D4A574
                : NSColor(srgbRed: 0.545, green: 0.271, blue: 0.075, alpha: 1.0) // #8B4513
        })
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.831, green: 0.647, blue: 0.455, alpha: 1.0) // #D4A574
                : UIColor(red: 0.545, green: 0.271, blue: 0.075, alpha: 1.0) // #8B4513
        })
        #endif
    }

    /// Subtle wash of the accent for hover/selection backgrounds.
    static var cruxAccentWash: Color { cruxAccent.opacity(0.10) }
}

extension LinearGradient {
    /// Brand gradient used for progress fills and decorative accents —
    /// bronze flowing into amber, echoing aged paper and ink.
    static var cruxProgress: LinearGradient {
        LinearGradient(
            colors: [Color.cruxAccent, Color.cruxAccent.opacity(0.65)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// Shared metrics so cards, rows, and bars use one spacing/radius language.
enum CruxMetrics {
    /// Corner radius for book covers and small cards.
    static let coverRadius: CGFloat = 7
    /// Corner radius for hover/selection card backgrounds.
    static let cardRadius: CGFloat = 12
}

/// Reading-progress capsule used by the library grid cards, list rows, and
/// the reader's navigation bar: brand gradient while in progress, solid
/// green once finished. One component so progress reads identically
/// everywhere.
struct CruxProgressBar: View {
    let fraction: Double
    var isFinished: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))

                if isFinished {
                    Capsule().fill(Color.green)
                } else {
                    Capsule()
                        .fill(LinearGradient.cruxProgress)
                        .frame(width: max(0, geo.size.width * min(1, max(0, fraction))))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Reading progress")
        .accessibilityValue(isFinished ? "Finished" : "\(Int(min(1, max(0, fraction)) * 100)) percent")
    }
}
