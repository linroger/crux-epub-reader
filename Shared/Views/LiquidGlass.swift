import SwiftUI

// MARK: - Liquid Glass / Materials shims
//
// macOS 26 introduces the Liquid Glass APIs (`glassEffect`, `glassEffect`-aware
// buttonStyles, `scrollEdgeEffectStyle`, etc). Because the app's deployment
// target is macOS 14.0, every site that adopts a Liquid Glass API must be
// guarded with a runtime availability check and fall back to a tasteful
// pre-26 treatment that uses standard Materials.
//
// Rather than scatter `#available` checks across dozens of call sites we
// centralize them here as small `ViewModifier`s plus convenience
// `View` extensions. Call sites read declaratively (e.g.
// `someView.cruxGlassCard()`), but at compile time the modifier holds the
// one and only availability branch.
//
// Pre-26 fallback design:
//   * Glass card  → translucent material + hairline border
//   * Toolbar    → bar material
//   * Floating   → regular material + soft shadow
//   * Soft edge  → no-op (scrollEdgeEffectStyle is purely a macOS 26 nicety)
//
// macOS 26 path uses `glassEffect(.regular.interactive(), in: ...)` so cards
// pick up real Liquid Glass lensing under SwiftUI's automatic recipe.

// MARK: Card

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
    }
}

// MARK: Floating (popovers, inspectors, AI cards)

private struct GlassFloatingModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
        } else {
            content
                .background(.thickMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
        }
    }
}

// MARK: Toolbar / chrome bar

private struct GlassBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            // Bar surfaces use the same glass treatment as cards so the
            // automatic recipe blends with the toolbar above.
            content.glassEffect(.regular, in: .rect(cornerRadius: 0))
        } else {
            content.background(.bar)
        }
    }
}

// MARK: Soft scroll edge

private struct SoftScrollEdgeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            content
        }
    }
}

// MARK: Buttons

private struct GlassButtonModifier: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}

// MARK: Sidebar background

private struct SidebarMaterialModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.background(.regularMaterial)
        } else {
            content.background(.bar)
        }
    }
}

// MARK: - Public surface

extension View {
    /// Card-style background that uses Liquid Glass on macOS 26+ and a
    /// translucent material with a hairline border on older systems.
    /// Use for inspector cards, settings sections, info chips.
    func cruxGlassCard(cornerRadius: CGFloat = 12, interactive: Bool = false) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, interactive: interactive))
    }

    /// Heavier glass surface intended for elements that float above
    /// scrolling content (popovers, inspectors). Adds a soft drop shadow.
    func cruxGlassFloating(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassFloatingModifier(cornerRadius: cornerRadius))
    }

    /// Toolbar/bar treatment for elements that sit at the top or bottom
    /// of a scene and need to feel attached to chrome.
    func cruxGlassBar() -> some View {
        modifier(GlassBarModifier())
    }

    /// Applies `scrollEdgeEffectStyle(.soft, for: .all)` on macOS 26+; no-op
    /// on older systems.
    func cruxScrollEdgeSoft() -> some View {
        modifier(SoftScrollEdgeModifier())
    }

    /// Liquid-glass button style on macOS 26+, bordered on older systems.
    func cruxGlassButton(prominent: Bool = false) -> some View {
        modifier(GlassButtonModifier(prominent: prominent))
    }

    /// Background appropriate for a sidebar pane.
    func cruxSidebarMaterial() -> some View {
        modifier(SidebarMaterialModifier())
    }
}

// MARK: - Cross-platform semantic colors
//
// AppKit's semantic `NSColor`s (`controlBackgroundColor`, `windowBackgroundColor`,
// `textBackgroundColor`, …) have no `Color(_:)` spelling on iOS, so
// `Color.cruxControlBackground` fails to compile in the iOS target. These
// helpers map each to the closest UIKit system color so shared views render on
// both platforms instead of being silently gated to macOS.
extension Color {
    /// Card / grouped-control background. macOS: `controlBackgroundColor`.
    static var cruxControlBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    /// Window / scene background. macOS: `windowBackgroundColor`.
    static var cruxWindowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    /// Editable text-field background. macOS: `textBackgroundColor`.
    static var cruxTextBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    /// Recessed / under-content background. macOS: `underPageBackgroundColor`.
    static var cruxUnderPageBackground: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(uiColor: .tertiarySystemBackground)
        #endif
    }
}
